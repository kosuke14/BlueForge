//
//  AudioPipeline.swift
//  BlueForge
//
//  Captures microphone audio via AVAudioEngine, converts it to the codec's
//  interleaved Int16 format, splits it into codec-sized frames, encodes, and
//  forwards frames to BLEAudioService.
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

    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var pcmBuffer = Data()

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
        var inputFormat = input.outputFormat(forBus: 0)
        if inputFormat.sampleRate == 0 {
            inputFormat = AVAudioFormat(standardFormatWithSampleRate: session.sampleRate,
                                        channels: AVAudioChannelCount(max(1, session.inputNumberOfChannels)))!
        }

        let target = codecManager.pcmFormat
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: target.sampleRate,
                                               channels: AVAudioChannelCount(target.channels),
                                               interleaved: true) else {
            throw CodecError.unsupportedFormat("bad capture format")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CodecError.encodingFailed("cannot create capture converter")
        }
        self.converter = converter
        self.targetFormat = targetFormat
        pcmBuffer.removeAll(keepingCapacity: true)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInput(buffer: buffer)
        }
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        targetFormat = nil
        pcmBuffer.removeAll(keepingCapacity: true)
        isRunning = false
    }

    private func handleInput(buffer: AVAudioPCMBuffer) {
        guard let codec = codecManager.current,
              let converted = convert(buffer),
              !converted.isEmpty else { return }

        let frameBytes = codec.pcmFrameBytes
        guard frameBytes > 0 else { return }
        pcmBuffer.append(converted)

        while pcmBuffer.count >= frameBytes {
            let chunk = Data(pcmBuffer.prefix(frameBytes))
            pcmBuffer.removeFirst(frameBytes)
            do {
                let frame = try codec.encode(pcm: chunk)
                ble.sendFrame(frame)
            } catch {
                log.error("encode failed: \(error.localizedDescription)")
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = converter, let targetFormat = targetFormat else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                            frameCapacity: capacity) else { return nil }

        var error: NSError?
        var supplied = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error = error {
            log.error("capture convert failed: \(error.localizedDescription)")
            return nil
        }
        guard status == .haveData || status == .inputRanDry, output.frameLength > 0 else { return nil }

        let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        let byteCount = Int(output.frameLength) * bytesPerFrame
        guard let base = output.int16ChannelData?[0] else { return nil }
        return Data(bytes: base, count: byteCount)
    }
}
