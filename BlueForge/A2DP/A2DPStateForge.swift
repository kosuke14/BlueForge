//
//  A2DPStateForge.swift
//  BlueForge
//
//  The "inventor loop": treat the sandbox escape not only as a reader but as a
//  possible writer. For every Bluetooth-related container the probe finds:
//    1. measure whether the kernel extension actually permits writes,
//    2. if yes, let the user edit codec-relevant plist keys in place
//       (transactional: backup first, rename-in, restore on failure),
//    3. persist an experiment history so results accumulate across builds.
//
//  On a read-only extension everything degrades gracefully to step 1 with an
//  honest log — the measurement itself is the discovery.
//

import Foundation
import Combine

struct ForgeHistoryRecord: Codable, Identifiable {
    let date: Date
    let target: String
    let changedKeys: [String]
    let writable: Bool
    let note: String

    var id: Date { date }
}

enum ForgeHistory {
    static var url: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forge_history.json")
    }

    static func load() -> [ForgeHistoryRecord] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([ForgeHistoryRecord].self, from: data)
        else { return [] }
        return list
    }

    static func append(_ record: ForgeHistoryRecord) {
        var list = load()
        list.append(record)
        if list.count > 200 { list.removeFirst(list.count - 200) }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

@MainActor
final class A2DPStateForge: ObservableObject {
    @Published var log: String = ""
    @Published var candidates: [ForgeCandidate] = []
    @Published var entries: [String] = []
    @Published var keyValues: [ForgeKeyValue] = []
    @Published var dirPath: String?
    @Published var filePath: String?
    @Published var filePathWritable = false
    @Published var allowAnyKey = false
    @Published var history: [ForgeHistoryRecord] = []

    weak var probe: A2DPProbe?

    private func append(_ line: String) {
        log += line + "\n"
    }

    struct ForgeCandidate: Identifiable {
        let id: UUID
        let path: String
        let owner: String
        let writable: Bool
        let note: String
    }

    // MARK: - Scan

    /// Enumerate all roots through the shared probe and measure writability of
    /// every Bluetooth-related container (bounded per root).
    func scan() {
        guard let probe else { append("probe not attached"); return }
        candidates = []
        entries = []
        keyValues = []
        dirPath = nil
        filePath = nil
        filePathWritable = false
        log = ""
        append("CodecForge scan — measuring write access, not assuming it.")

        Task { [weak self] in
            guard let self else { return }
            // Bluetooth state lives outside the container system; measure the
            // known system directories directly.
            for dir in BluetoothSystemPath.dirs {
                let (writable, note) = self.probeWritable(dir)
                guard note != "no extension" else {
                    self.append("inaccessible: \(dir)")
                    continue
                }
                self.append("\(writable ? "WRITABLE" : "read-only") \(dir) (\(note))")
                self.candidates.append(.init(id: UUID(), path: dir,
                                             owner: (dir as NSString).lastPathComponent,
                                             writable: writable, note: note))
            }
            self.append("scan finished — \(self.candidates.count) candidates")
        }
    }

    /// Honest write measurement: create a uniquely-named marker file inside the
    /// escaped path and delete it again. Never touches existing content.
    func probeWritable(_ path: String) -> (Bool, String) {
        guard let probe else { return (false, "probe not attached") }
        let handle = probe.consumeFor(path)
        guard handle > 0 else { return (false, "no extension") }
        defer { SandboxExtensionRelease(handle) }

        var isDir: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return (false, "target missing")
        }

        let marker = isDir.boolValue
            ? path + "/.bfw_" + String(UUID().uuidString.prefix(8))
            : (path as NSString).deletingLastPathComponent + "/.bfw_" + String(UUID().uuidString.prefix(8))

        let created = fm.createFile(atPath: marker, contents: Data("x".utf8))
        if created {
            try? fm.removeItem(atPath: marker)
            return (true, "marker created+removed")
        }
        return (false, "createFile refused")
    }

    // MARK: - Inspect

    /// Open a container directory for browsing.
    func inspectDir(_ path: String) {
        guard let probe else { append("probe not attached"); return }
        entries = probe.listDir(path)
        dirPath = path
        append("opened \(path) — \(entries.count) entries")
    }

    /// Load a candidate file for editing.
    func inspectFile(_ path: String, dir: String) {
        guard let probe else { append("probe not attached"); return }
        filePath = path
        keyValues = []

        let (writable, note) = probeWritable(dir)
        filePathWritable = writable
        append("\(writable ? "WRITABLE" : "read-only") target \(path) (\(note))")

        let handle = probe.consumeFor(path)
        guard handle > 0 else {
            append("cannot open \(path)")
            return
        }
        defer { SandboxExtensionRelease(handle) }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            append("unreadable: \(path)")
            return
        }
        do {
            let (root, _) = try PLISTForge.parse(data)
            keyValues = PLISTForge.keyValues(root: root, codecOnly: !allowAnyKey)
            append("parsed \(keyValues.count) edit\(keyValues.count == 1 ? "" : "s") (format preserved on write)")
        } catch {
            append("not a plist / parse failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Forge

    /// Transactional write-back: backup `path` as `path.bf.bak`, then rename a
    /// freshly serialised tmp file into place; restore on failure.
    func forge(restoreOriginal: Bool = false) {
        genericForge(restoreOriginal: restoreOriginal)
    }

    /// Original rename-based path for A2DP state containers (marker-verified
    /// writable directories).
    private func genericForge(restoreOriginal: Bool) {
        guard let probe, let path = filePath else { return }
        let dir = (path as NSString).deletingLastPathComponent

        let handle = probe.consumeFor(dir)
        guard handle > 0 else {
            append("forge refused: no extension for \(dir)")
            ForgeHistory.append(.init(date: Date(), target: path,
                                      changedKeys: [], writable: false,
                                      note: "no extension"))
            history = ForgeHistory.load()
            return
        }
        defer { SandboxExtensionRelease(handle) }

        let fm = FileManager.default
        do {
            let original = try Data(contentsOf: URL(fileURLWithPath: path))
            let (root, format) = try PLISTForge.parse(original)
            var mutableRoot: Any = root

            if restoreOriginal {
                guard let backupURL = lastBackupURL(path),
                      let backupData = try? Data(contentsOf: backupURL) else {
                    append("no backup available to restore")
                    return
                }
                try moveIntoPlace(backupData, target: path, in: dir, fm: fm)
                append("restored original from backup: \(path)")
                ForgeHistory.append(.init(date: Date(), target: path,
                                          changedKeys: [], writable: true,
                                          note: "restored from backup"))
                history = ForgeHistory.load()
                return
            }

            let changed = PLISTForge.apply(&mutableRoot, edits: keyValues)
            guard !changed.isEmpty else {
                append("nothing changed — refusing no-op write")
                return
            }
            let newData = try PLISTForge.serialise(mutableRoot, format: format)

            let backupPath = path + ".bf.bak"
            let backupURL = URL(fileURLWithPath: backupPath)
            if !fm.fileExists(atPath: backupPath) {
                try original.write(to: backupURL, options: .atomic)
                append("backup written: \(backupPath)")
            }

            try moveIntoPlace(newData, target: path, in: dir, fm: fm)
            append("forged \(path) — \(changed.count) key\(changed.count == 1 ? "" : "s"): "
                   + changed.map { $0.joined(separator: ".") }.sorted().joined(separator: ", "))
            append("toggle Bluetooth (Control Center off/on) so bluetoothd reloads its state before judging the result.")

            ForgeHistory.append(.init(date: Date(), target: path,
                                      changedKeys: changed.map { $0.joined(separator: ".") }.sorted(),
                                      writable: true, note: "forged"))
            history = ForgeHistory.load()
        } catch {
            append("forge failed: \(error.localizedDescription)")
            restoreFromBackup(path, dir: dir, fm: fm)
            ForgeHistory.append(.init(date: Date(), target: path,
                                      changedKeys: [], writable: false,
                                      note: "failed: \(error.localizedDescription)"))
            history = ForgeHistory.load()
        }
    }


    private func moveIntoPlace(_ data: Data, target: String, in dir: String, fm: FileManager) throws {
        let tmp = dir + "/.bf.tmp_" + String(UUID().uuidString.prefix(8))
        let tmpURL = URL(fileURLWithPath: tmp)
        let targetURL = URL(fileURLWithPath: target)
        try data.write(to: tmpURL, options: .atomic)
        do {
            _ = try fm.replaceItemAt(targetURL, withItemAt: tmpURL, backupItemName: nil)
        } catch {
            try? fm.removeItem(atPath: tmp)
            throw error
        }
        try? fm.removeItem(atPath: tmp)
    }

    private func lastBackupURL(_ path: String) -> URL? {
        let backupPath = path + ".bf.bak"
        let fm = FileManager.default
        return fm.fileExists(atPath: backupPath) ? URL(fileURLWithPath: backupPath) : nil
    }

    private func restoreFromBackup(_ path: String, dir: String, fm: FileManager) {
        guard let backupURL = lastBackupURL(path),
              let backupData = try? Data(contentsOf: backupURL) else {
            append("no backup to restore from")
            return
        }
        do {
            try moveIntoPlace(backupData, target: path, in: dir, fm: fm)
            append("restored original after failure")
        } catch {
            append("restore failed too — backup still at \(backupURL.path)")
        }
    }
}
