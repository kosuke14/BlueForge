//
//  SystemProbeView.swift
//  BlueForge
//
//  Console-style UI for the worse_query-style sandbox enumeration and the
//  A2DP hook coordinator. Read-only on jailed devices by design.
//

import SwiftUI

struct SystemProbeView: View {
    @StateObject private var probe = A2DPProbe()
    @StateObject private var hook = A2DPHookCoordinator()
    @State private var appGroup = "group.com.blueforge.app"

    var body: some View {
        Form {
            Section("App Group (escape vehicle)") {
                TextField("group identifier", text: $appGroup)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
                Text("Must match the entitlement of the installed build (group.com.blueforge.app). The containermanagerd trick in docs/SANDBOX_A2DP.md needs an App Group you own.")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Section("Probe") {
                Button(probe.running ? "Probing…" : "Run A2DP state probe") {
                    probe.appGroupOverride = appGroup == "group.com.blueforge.app" ? nil : appGroup
                    probe.runFullProbe()
                }
                .disabled(probe.running)

                if !probe.findings.isEmpty {
                    NavigationLink("Findings (\(probe.findings.count))") {
                        List(probe.findings) { finding in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(finding.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                ForEach(finding.summaryLines, id: \.self) { line in
                                    Text("  " + line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }

            Section("Hooks") {
                NavigationLink("Open CodecForge (attempt write)") {
                    ForgeView()
                }
                ForEach(A2DPHookStrategy.allCases) { strategy in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(strategy.rawValue)
                            Spacer()
                            Text(strategy.feasibleJailed ? " jailed" : " NOT jailed")
                                .font(.caption2)
                                .foregroundColor(strategy.feasibleJailed ? .green : .red)
                        }
                        Text(strategy.detail)
                            .font(.caption2).foregroundColor(.secondary)
                        if let result = hook.results.first(where: { $0.strategy == strategy }) {
                            Text((result.success ? "+ " : "- ") + result.message)
                                .font(.caption2)
                                .foregroundColor(result.success ? .green : .orange)
                        }
                    }
                }
                Button("Arm hooks") { hook.activateAll() }
                if !hook.routeLog.isEmpty {
                    ForEach(Array(hook.routeLog.suffix(10).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Log") {
                ScrollView {
                    Text(probe.log.isEmpty ? "(idle)" : probe.log)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 220)

                ShareLink(item: probe.exportText) {
                    Text("Share log")
                }

                Button("Clear log") {
                    probe.log = ""
                    probe.findings = []
                }
            }
        }
        .navigationTitle("A2DP system probe")
        .navigationBarTitleDisplayMode(.inline)
    }
}
