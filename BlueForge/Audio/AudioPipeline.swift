//
//  AudioPipeline.swift
//  BlueForge
//
//  Plays a media file through the codec pipeline: AVAudioFile -> AVAudioConverter
//  (to the codec's interleaved Int16 PCM format) -> codec frames -> BLE.
//  High-resolution sources (e.g. 96 kHz / 24-bit FLAC) are read at their native
//  rate and converted to the configured codec format.
//  There is intentionally no microphone path: the app streams media, it does
//  not capture input.
//

import Foundation
import AVFoundation
import Combine
import os

final class AudioPipeline: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var fileName: String?
    @Published var progress: Double = 0        // 0...1
    @Published var duration: Double = 0
    @Published var lastError: String?

    private let codecManager: CodecManager
    private let ble: BLEAudioService
    private let log = Logger(subsystem: "com.blueforge", category: "audio")

    private var readerQueue: DispatchQueue?
    private var file: AVAudioFile?

    init(codecManager: CodecManager, ble: BLEAudioService) {
        self.codecManager = codecManager
        self.ble = ble
    }

    /// Stream a media file in real time to the connected BLE receiver.
    func startPlayback(url: URL) throws {
        guard ble.connected else {
            throw CodecError.unsupportedFormat("BLE receiver is not connected")
        }
        guard codecManager.current != nil else {
            throw CodecError.unsupportedFormat("codec not configured")
        }
        guard codecManager.lastError == nil else {
            throw CodecError.unsupportedFormat(codecManager.lastError ?? "codec error")
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP])
        try session.setActive(true)

        stop()

        let audioFile = try AVAudioFile(forReading: url)
        let sourceFormat = audioFile.processingFormat
        duration = Double(audioFile.length) / sourceFormat.sampleRate

        let target = codecManager.pcmFormat
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: target.sampleRate,
                                               channels: AVAudioChannelCount(target.channels),
                                               interleaved: true) else {
            throw CodecError.unsupportedFormat("bad target format")
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw CodecError.unsupportedFormat("cannot create file converter")
        }

        file = audioFile
        fileName = url.lastPathComponent
        progress = 0
        lastError = nil
        isRunning = true

        let queue = DispatchQueue(label: "com.blueforge.playback", qos: .userInitiated)
        readerQueue = queue

        let chunkFrames: AVAudioFrameCount = 4096
        queue.async { [weak self] in
            self?.readLoop(file: audioFile, converter: converter,
                           sourceFormat: sourceFormat, targetFormat: targetFormat,
                           chunkFrames: chunkFrames)
        }
    }

    func stop() {
        readerQueue?.suspend()
        readerQueue = nil
        file = nil
        isRunning = false
        progress = 0
        duration = 0
    }

    // MARK: - Reader loop

    private func readLoop(file: AVAudioFile,
                          converter: AVAudioConverter,
                          sourceFormat: AVAudioFormat,
                          targetFormat: AVAudioFormat,
                          chunkFrames: AVAudioFrameCount) {
        guard let codec = codecManager.current else { finish(error: "codec missing"); return }
        let frameBytes = codec.pcmFrameBytes
        guard frameBytes > 0 else { finish(error: "codec frame size unknown"); return }

        let totalFrames = file.length
        let sampleRate = sourceFormat.sampleRate
        let startDate = Date()
        var carry = Data()
        var playedFrames: AVAudioFramePosition = 0

        while isRunning {
            let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                          frameCapacity: chunkFrames)
            guard let buffer else { finish(error: "buffer alloc failed"); return }
            do {
                try file.read(into: buffer, frameCount: chunkFrames)
            } catch {
                // A clean EOF surfaces as a read error in some container formats.
                break
            }
            guard buffer.frameLength > 0 else { break }
            playedFrames += AVAudioFramePosition(buffer.frameLength)

            let converted = convert(buffer: buffer, converter: converter,
                                    targetFormat: targetFormat)
            guard !converted.isEmpty else { continue }
            carry.append(converted)

            while carry.count >= frameBytes {
                let piece = carry.prefix(frameBytes)
                carry.removeFirst(frameBytes)
                do {
                    let encoded = try codec.encode(pcm: Data(piece))
                    if !encoded.isEmpty { ble.sendFrame(encoded) }
                } catch {
                    log.error("encode failed: \(error.localizedDescription)")
                }
            }

            // Real-time pacing so BLE receives a steady stream instead of the
            // whole file at once.
            let target = Double(playedFrames) / sampleRate
            let elapsed = -startDate.timeIntervalSinceNow
            if elapsed < target {
                Thread.sleep(forTimeInterval: min(target - elapsed, 0.1))
            }

            let progressValue = totalFrames > 0 ? min(1, Double(playedFrames) / Double(totalFrames)) : 0
            DispatchQueue.main.async { [weak self] in
                self?.progress = progressValue
            }
        }

        finish(error: nil)
    }

    private func finish(error message: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let message { self.lastError = message }
            self.isRunning = false
        }
    }

    // MARK: - Conversion

    private func convert(buffer: AVAudioPCMBuffer,
                         converter: AVAudioConverter,
                         targetFormat: AVAudioFormat) -> Data {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                            frameCapacity: capacity) else { return Data() }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error {
            log.error("convert failed: \(error.localizedDescription)")
            return Data()
        }
        guard status == .haveData || status == .inputRanDry, output.frameLength > 0 else { return Data() }

        let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        let byteCount = Int(output.frameLength) * bytesPerFrame
        guard let base = output.int16ChannelData?[0] else { return Data() }
        return Data(bytes: base, count: byteCount)
    }
}
