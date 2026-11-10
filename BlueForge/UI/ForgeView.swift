//
//  ForgeView.swift
//  BlueForge
//
//  CodecForge UI: run the writability scan, browse an escaped container,
//  edit codec-relevant plist keys, write back with automatic backup, and
//  review the experiment history.
//

import SwiftUI

struct ForgeView: View {
    @StateObject private var probe = A2DPProbe()
    @StateObject private var forge = A2DPStateForge()
    @State private var appGroup: String = "group.com.blueforge.app"

    var body: some View {
        Form {
            Section("App Group (escape vehicle)") {
                TextField("group identifier", text: $appGroup)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
            }

            Section("1. Scan (write access is measured)") {
                Button("Scan Bluetooth containers") {
                    probe.appGroupOverride =
                        appGroup == "group.com.blueforge.app" ? nil : appGroup
                    forge.probe = probe
                    forge.scan()
                }
                .disabled(probe.running)

                ForEach(forge.candidates) { candidate in
                    Button(candidate.path) {
                        forge.inspectDir(candidate.path)
                    }
                    .foregroundColor(candidate.writable ? .green : .secondary)
                    HStack {
                        Text(candidate.writable
                             ? "WRITABLE — " + candidate.note
                             : "read-only — " + candidate.note)
                            .font(.caption2)
                            .foregroundColor(candidate.writable ? .green : .orange)
                    }
                }
            }

            if let dir = forge.dirPath {
                Section("2. Entries in \(dir)") {
                    ForEach(forge.entries, id: \.self) { entry in
                        Button(entry) {
                            let full = dir.hasSuffix("/")
                                ? dir + entry
                                : dir + "/" + entry
                            forge.inspectFile(full, dir: dir)
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            if let path = forge.filePath, forge.filePathWritable {
                Section("3. Edit \(path)") {
                    Toggle("Show all keys (not only codec)", isOn: $forge.allowAnyKey)
                        .onChange(of: forge.allowAnyKey) { _ in reload() }

                    ForEach($forge.keyValues) { $kv in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kv.display)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                            TextField(kv.originalText, text: $kv.editedText)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }

                    Button("Write back (backup auto)") { forge.forge() }
                    Button("Restore from backup") { forge.forge(restoreOriginal: true) }
                    Text("Values are re-typed as bool/int/double when they parse as such, otherwise as string. A .bf.bak copy is kept on first write and direct writes replace the file atomically.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            Section("History") {
                if forge.history.isEmpty {
                    Text("(no experiments yet)").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(Array(forge.history.suffix(20).reversed())) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.target).font(.system(.caption2, design: .monospaced))
                            Text("\(record.date) — \(record.note) — \(record.changedKeys.joined(separator: ", "))")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    ShareLink(item: historyExport) {
                        Text("Share history")
                    }
                }
            }

            Section("Forge log") {
                ScrollView {
                    Text(forge.log.isEmpty ? "(idle)" : forge.log)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
            }
        }
        .navigationTitle("CodecForge")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historyExport: String {
        var text = "BlueForge CodecForge history\n"
        for record in forge.history {
            text += "\(record.date) \(record.target) [\(record.writable ? "W" : "R")] \(record.note) \(record.changedKeys.joined(separator: ","))\n"
        }
        return text
    }

    private func reload() {
        guard let path = forge.filePath, let dir = forge.dirPath else { return }
        forge.inspectFile(path, dir: dir)
    }
}
