//
//  ContentView.swift
//  BlueForge
//

import SwiftUI
import CoreBluetooth
import os

enum AudioRole: String, CaseIterable, Identifiable {
    case sender = "Sender"
    case receiver = "Receiver"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var codecManager: CodecManager
    @StateObject private var ble: BLEAudioService
    @StateObject private var pipeline: AudioPipeline
    @StateObject private var receiver: ReceiverPipeline

    @State private var role: AudioRole = .sender
    @State private var bitrateKbps: Int = 320
    @State private var sampleRate: Int = 48000
    @State private var channels: Int = 2
    @AppStorage("bf.hasSeenGuide") private var hasSeenGuide = false
    @State private var showGuideSheet = false

    init() {
        let cm = CodecManager()
        let b = BLEAudioService()
        _codecManager = StateObject(wrappedValue: cm)
        _ble = StateObject(wrappedValue: b)
        _pipeline = StateObject(wrappedValue: AudioPipeline(codecManager: cm, ble: b))
        _receiver = StateObject(wrappedValue: ReceiverPipeline(codecManager: cm))
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Start here") {
                    NavigationLink {
                        guide
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill")
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("高音質コーデック配信ガイド")
                                    .font(.subheadline.weight(.semibold))
                                Text("目的だけを 5 ステップで設定 (初回起動時に自動表示)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Mode") {
                    Picker("Role", selection: $role) {
                        ForEach(AudioRole.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(role == .sender
                         ? "Send microphone audio to another iPhone / BLE receiver."
                         : "Receive audio from another iPhone and play it here.")
                        .font(.caption).foregroundColor(.secondary)
                }

                Section("Codec") {
                    Picker("Selected", selection: $codecManager.selected) {
                        ForEach(CodecID.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    HStack {
                        Text("AOSP-available")
                        Spacer()
                        Text(codecManager.selected.aospAvailable ? "Yes" : "No (proprietary)")
                            .foregroundColor(codecManager.selected.aospAvailable ? .green : .orange)
                    }
                    HStack {
                        Text("Native iOS encoder")
                        Spacer()
                        Text(codecManager.selected.nativeIOSEncoder ? "Yes" : "No")
                            .foregroundColor(.secondary)
                    }
                    if let err = codecManager.lastError {
                        Text(err).foregroundColor(.red).font(.caption)
                    }
                    let info = codecManager.selected.info
                    Text(info.notes).font(.caption).foregroundColor(.secondary)
                    HStack {
                        Text("Max SR: \(info.maxSampleRate) Hz").font(.caption2)
                        Spacer()
                        Text("Max: \(info.maxBitrateKbps) kbps").font(.caption2)
                        Spacer()
                        Text("Latency: \(info.latencyMs) ms").font(.caption2)
                    }.foregroundColor(.secondary)
                }

                Section("Format") {
                    Picker("Sample rate", selection: $sampleRate) {
                        ForEach([16000, 32000, 44100, 48000, 96000], id: \.self) { r in
                            Text("\(r) Hz").tag(r)
                        }
                    }
                    .onChange(of: sampleRate) { _ in applyFormat() }
                    Picker("Channels", selection: $channels) {
                        Text("Mono").tag(1)
                        Text("Stereo").tag(2)
                    }
                    .onChange(of: channels) { _ in applyFormat() }
                    Picker("Bitrate", selection: $bitrateKbps) {
                        ForEach([128, 192, 256, 320, 512, 990], id: \.self) { b in
                            Text("\(b) kbps").tag(b)
                        }
                    }
                    .onChange(of: bitrateKbps) { _ in applyFormat() }
                }

                Section {
                    NavigationLink("上級: システム探索/Forge (sandbox 調査)") {
                        SystemProbeView()
                    }
                    Text("主目的には不要です。worse_query 技法による Bluetooth 状態の列挙/読取や、実測された書き込み実験 (任意) を行えます。詳しくは docs/SANDBOX_A2DP.md・docs/CODECFORGE.md。")
                        .font(.caption2).foregroundColor(.secondary)
                }

                if role == .sender {
                    Section("Bluetooth (BLE)") {
                        Text("State: \(stateString(ble.state))")
                        HStack {
                            Text("Connected")
                            Spacer()
                            Text(ble.connected ? "Yes" : "No").foregroundColor(ble.connected ? .green : .secondary)
                        }
                        Button(ble.connected ? "Disconnect" : "Scan") {
                            if ble.connected { ble.disconnect() } else { ble.startScan() }
                        }
                        List(ble.discoveredPeripherals, id: \.identifier) { p in
                            Button(p.name ?? p.identifier.uuidString) { ble.connect(p) }
                        }
                    }

                    Section("Audio") {
                        Button(pipeline.isRunning ? "Stop Capture" : "Start Capture") {
                            if pipeline.isRunning {
                                pipeline.stop()
                            } else {
                                do { try pipeline.startCapture() }
                                catch { /* logged in pipeline */ }
                            }
                        }
                    }
                } else {
                    Section("Receiver (BLE)") {
                        Text("State: \(stateString(receiver.peripheralState))")
                        HStack {
                            Text("Advertising")
                            Spacer()
                            Text(receiver.isAdvertising ? "Yes" : "No")
                                .foregroundColor(receiver.isAdvertising ? .green : .secondary)
                        }
                        HStack {
                            Text("Subscribers")
                            Spacer()
                            Text("\(receiver.subscriberCount)")
                        }
                        Button(receiver.isRunning ? "Stop Receiver" : "Start Receiver") {
                            if receiver.isRunning { receiver.stop() } else { receiver.start() }
                        }
                        if let err = receiver.lastError {
                            Text(err).font(.caption).foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("BlueForge")
        }
        .onAppear {
            applyFormat()
            if !hasSeenGuide { showGuideSheet = true }
        }
        .sheet(isPresented: $showGuideSheet, onDismiss: { hasSeenGuide = true }) {
            NavigationView { guide }
        }
        .onChange(of: role) { _ in
            if pipeline.isRunning { pipeline.stop() }
            if receiver.isRunning { receiver.stop() }
        }
    }

    private var guide: some View {
        GuideView(role: $role, bitrateKbps: $bitrateKbps, sampleRate: $sampleRate,
                  channels: $channels,
                  codecManager: codecManager, ble: ble, pipeline: pipeline, receiver: receiver)
    }

    private func applyFormat() {
        codecManager.configure(
            format: PCMFormat(sampleRate: Double(sampleRate), channels: channels, bitsPerSample: 16),
            bitrate: bitrateKbps * 1000
        )
    }

    private func stateString(_ s: CBManagerState) -> String {
        switch s {
        case .poweredOn: return "Powered On"
        case .poweredOff: return "Powered Off"
        case .resetting: return "Resetting"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        default: return "Unknown"
        }
    }
}
