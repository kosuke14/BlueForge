//
//  ContentView.swift
//  BlueForge
//

import SwiftUI
import CoreBluetooth
import os

struct ContentView: View {
    @StateObject private var codecManager: CodecManager
    @StateObject private var ble: BLEAudioService
    @StateObject private var pipeline: AudioPipeline

    @State private var bitrateKbps: Int = 320
    @State private var sampleRate: Int = 48000
    @State private var channels: Int = 2

    init() {
        let cm = CodecManager()
        let b = BLEAudioService()
        _codecManager = StateObject(wrappedValue: cm)
        _ble = StateObject(wrappedValue: b)
        _pipeline = StateObject(wrappedValue: AudioPipeline(codecManager: cm, ble: b))
    }

    var body: some View {
        NavigationView {
            Form {
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
            }
            .navigationTitle("BlueForge")
        }
        .onAppear { applyFormat() }
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
