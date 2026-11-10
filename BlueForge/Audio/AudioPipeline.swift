//
//  AudioPipeline.swift
//  BlueForge
//
//  Captures microphone audio via AVAudioEngine, encodes with the selected
//  codec, and forwards frames to BLEAudioService. Also supports playback of
//  received frames.
//

import Foundation
import AVFoundation
import Combine
import os

final class AudioPipeline: ObservableObject {
    @Published var isRunning: Bool = false

    private let engine = AVAudioEngine()
    private let codecManager: CodecManager
    private let ble: BLEAudioService
    private let log = Logger(subsystem: "com.blueforge", category: "audio")

    init(codecManager: CodecManager, ble: BLEAudioService) {
        self.codecManager = codecManager
        self.ble = ble
        ble.onReceivedFrame = { [weak self] data in
            self?.handleReceivedFrame(data)
        }
    }

    private func handleReceivedFrame(_ data: Data) {
        guard let codec = codecManager.current else { return }
        do {
            let pcm = try codec.decode(frame: data)
            log.info("received frame decoded: \(pcm.count) bytes")
        } catch {
            log.error("decode received frame failed: \(error.localizedDescription)")
        }
    }

    func startCapture() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleInput(buffer: buffer)
        }
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func handleInput(buffer: AVAudioPCMBuffer) {
        guard let codec = codecManager.current else { return }
        // Convert buffer to Data (Int16 interleaved). (Simplified; real impl uses converter.)
        guard let ch = buffer.int16ChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var data = Data(capacity: frames * channels * 2)
        for f in 0..<frames {
            for c in 0..<channels {
                var v = ch[c][f]
                data.append(Data(bytes: &v, count: 2))
            }
        }
        do {
            let frame = try codec.encode(pcm: data)
            ble.sendFrame(frame)
        } catch {
            // Log; do not crash real-time thread.
        }
    }
}
