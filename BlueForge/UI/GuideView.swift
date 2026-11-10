//
//  GuideView.swift
//  BlueForge
//
//  Visual, goal-only tutorial: stream LDAC (or any supported codec) audio over
//  BLE to a receiver. Everything the user needs for the primary goal lives
//  here, with live status so the next action is always obvious. Advanced
//  sandbox research is intentionally NOT part of this flow.
//

import SwiftUI
import CoreBluetooth
import UniformTypeIdentifiers

struct GuideView: View {
    @Binding var role: AudioRole
    @Binding var bitrateKbps: Int
    @Binding var sampleRate: Int
    @Binding var channels: Int
    @ObservedObject var codecManager: CodecManager
    @ObservedObject var ble: BLEAudioService
    @ObservedObject var pipeline: AudioPipeline
    @ObservedObject var receiver: ReceiverPipeline
    @State private var showImporter = false
    @State private var mediaURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                goalCard
                progressHeader
                stepCard(index: 1, "役割を選ぶ", done: true) {
                    Picker("Role", selection: $role) {
                        ForEach(AudioRole.allCases) { r in Text(r.rawValue).tag(r) }
                    }
                    .pickerStyle(.segmented)
                    Text(role == .sender
                         ? "この iPhone がスピーカー/レシーバーへ音声を送ります。"
                         : "この iPhone がサウンドを出力します(もう一台が送信)。")
                        .font(.caption).foregroundColor(.secondary)
                }

                stepCard(index: 2, "コーデックを選ぶ", done: codecManager.lastError == nil) {
                    Picker("Codec", selection: $codecManager.selected) {
                        ForEach(CodecID.allCases) { c in Text(c.rawValue).tag(c) }
                    }
                    .pickerStyle(.segmented)
                    if codecManager.selected == .ldac {
                        Text("LDAC は高ビットレート(990kbps)で BLE に対しては重め。安定しない場合は AAC/SBC 256kbps から始めてください。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if let err = codecManager.lastError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }

                stepCard(index: 3, "フォーマットを両端で一致させる", done: true) {
                    HStack {
                        Picker("SR", selection: $sampleRate) {
                            ForEach([16000, 32000, 44100, 48000, 96000], id: \.self) { r in
                                Text("\(r)").tag(r)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: sampleRate) { _ in applyFormat() }

                        Picker("Ch", selection: $channels) {
                            Text("Mono").tag(1)
                            Text("Stereo").tag(2)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: channels) { _ in applyFormat() }

                        Picker("kbps", selection: $bitrateKbps) {
                            ForEach([128, 192, 256, 320, 512, 990], id: \.self) { b in
                                Text("\(b)").tag(b)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: bitrateKbps) { _ in applyFormat() }
                    }
                    Text("受信側アプリで同じ値(コーデック/Hz/チャンネル/kbps)を選んでください。自動ネゴシエーションはありません。")
                        .font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(formatChips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }

                if role == .sender {
                    stepCard(index: 4, "BLE: 相手に接続", done: ble.state == .poweredOn && ble.connected) {
                        Text("State: \(stateString(ble.state))")
                            .font(.caption).foregroundColor(.secondary)
                        Button(ble.connected ? "切断" : "スキャンして接続") {
                            if ble.connected { ble.disconnect() } else { ble.startScan() }
                        }
                        .buttonStyle(.bordered)
                        if !ble.connected {
                            ForEach(ble.discoveredPeripherals, id: \.identifier) { p in
                                Button {
                                    ble.connect(p)
                                } label: {
                                    HStack {
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                        Text(p.name ?? p.identifier.uuidString)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                    stepCard(index: 5, "音源ファイルを選んで配信開始", done: pipeline.isRunning) {
                        Button {
                            showImporter = true
                        } label: {
                            Label("ファイルを選ぶ", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        if let name = pipeline.fileName {
                            Text(name).font(.caption).foregroundColor(.secondary)
                            ProgressView(value: pipeline.progress)
                        }
                        Button {
                            if pipeline.isRunning {
                                pipeline.stop()
                            } else if let url = mediaURL {
                                do { try pipeline.startPlayback(url: url) }
                                catch { pipeline.lastError = error.localizedDescription }
                            }
                        } label: {
                            Label(pipeline.isRunning ? "停止" : "再生して配信",
                                  systemImage: pipeline.isRunning ? "stop.fill" : "play.fill")
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mediaURL == nil && !pipeline.isRunning)
                        if let err = pipeline.lastError {
                            Text(err).font(.caption).foregroundColor(.red)
                        }
                    }
                } else {
                    stepCard(index: 4, "受信を開始(待ち受け)", done: receiver.isAdvertising) {
                        Button {
                            if receiver.isRunning { receiver.stop() } else { receiver.start() }
                        } label: {
                            Label(receiver.isRunning ? "停止" : "レシーバー起動",
                                  systemImage: receiver.isRunning ? "stop.fill" : "speaker.wave.2.fill")
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        HStack {
                            Text("待受中")
                            Spacer()
                            Text(receiver.isAdvertising ? "Yes" : "No")
                                .foregroundColor(receiver.isAdvertising ? .green : .secondary)
                        }
                        .font(.caption)
                        if let err = receiver.lastError {
                            Text(err).font(.caption).foregroundColor(.red)
                        }
                    }

                    stepCard(index: 5, "音を受け取って再生", done: receiver.isRunning && receiver.isAdvertising) {
                        Text("送信側から本デバイス(BlueForge RX)を選ぶと、コーデック済みフレームを受信して再生します。両アプリはフォアグラウンド推奨です。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                honestyCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("スタートガイド")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                mediaURL = url
                do { try pipeline.startPlayback(url: url) }
                catch { pipeline.lastError = error.localizedDescription }
            }
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("目的: 高音質コーデックで iPhone から音を送る", systemImage: "target").font(.headline)
            Text("LDAC / SBC / AAC / LC3 をこのアプリ自身がエンコードし、BLE で受信側へストリーミングします。通常のヘッドフォン向きの A2DP ネゴシエーションは iOS システム管理のため対象外です。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.12)))
    }

    private var totalSteps: Int { 5 }
    private var completedSteps: Int {
        var n = 2 // steps 1 and 3 are configuration confirmations
        if codecManager.lastError == nil { n += 1 }
        if role == .sender {
            if ble.state == .poweredOn && ble.connected { n += 1 }
            if pipeline.isRunning { n += 1 }
        } else {
            if receiver.isAdvertising { n += 1 }
            if receiver.isRunning && receiver.isAdvertising { n += 1 }
        }
        return n
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("進捗 \(completedSteps)/\(totalSteps)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if completedSteps == totalSteps {
                    Label("配信中", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            ProgressView(value: Double(completedSteps), total: Double(totalSteps))
                .tint(completedSteps == totalSteps ? .green : .accentColor)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var formatChips: [String] {
        ["\(codecManager.selected.rawValue)",
         "\(sampleRate) Hz",
         channels == 2 ? "Stereo" : "Mono",
         "\(bitrateKbps) kbps"]
    }

    private var honestyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("正直なスコープ", systemImage: "info.circle").font(.subheadline.weight(.semibold))
            Text("市販ヘッドフォンとの Bluetooth Classic A2DP コーデック(LDAC/aptX 等)の選択は、脱獄無しのこのアプリからは変更できません(iOS がシステム側で決定)。このガイドの配信は、BlueForge 受信アプリや BLE 対応レシーバーのために設計されています。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func stepCard(index: Int, _ title: String, done: Bool,
                          @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.15))
                    .frame(width: 30, height: 30)
                if done {
                    Image(systemName: "checkmark")
                        .font(.footnote.bold()).foregroundColor(.green)
                } else {
                    Text("\(index)").font(.footnote.bold()).foregroundColor(.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
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

    private func applyFormat() {
        codecManager.configure(
            format: PCMFormat(sampleRate: Double(sampleRate), channels: channels, bitsPerSample: 16),
            bitrate: bitrateKbps * 1000
        )
    }
}
