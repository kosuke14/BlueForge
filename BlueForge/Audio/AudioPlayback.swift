//
//  AudioPlayback.swift
//  BlueForge
//
//  Plays decoded interleaved Int16 PCM through AVAudioEngine.
//

import Foundation
import AVFoundation

final class AudioPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var attached = false

    // USB-DAC-style rate handling: request the codec's native rate via
    // AVAudioSession and report what the route actually runs at. USB audio
    // routes honour >48 kHz; speaker/BT routes fall back to their own cap
    // (48 kHz) — the engine resamples, nothing is lost or faked.
    private(set) var requestedRate: Double = 48000
    private(set) var actualRate: Double = 0
    private(set) var routeName: String = ""

    func start(sampleRate: Double, channels: Int) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP])

        let clamped = min(max(sampleRate, 8000), 384_000)
        try session.setPreferredSampleRate(clamped)
        try session.setActive(true)

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                      channels: AVAudioChannelCount(channels)) else {
            throw CodecError.unsupportedFormat("bad playback format")
        }

        if !attached {
            engine.attach(player)
            attached = true
        }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        try engine.start()
        player.play()
        format = fmt

        requestedRate = clamped
        actualRate = session.sampleRate
        routeName = session.currentRoute.outputs.first?.portName ?? "unknown"
    }

    func play(pcm: Data) {
        guard let fmt = format else { return }
        let channels = Int(fmt.channelCount)
        let bytesPerFrame = channels * 2
        let frames = pcm.count / bytesPerFrame
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: fmt,
                                            frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let src = base.assumingMemoryBound(to: Int16.self)
            for ch in 0..<channels {
                let dst = out[ch]
                for i in 0..<frames {
                    dst[i] = Float(src[i * channels + ch]) / 32768.0
                }
            }
        }

        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        player.stop()
        engine.stop()
        format = nil
    }
}
