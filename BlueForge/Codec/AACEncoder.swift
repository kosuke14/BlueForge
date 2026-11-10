//
//  AACEncoder.swift
//  BlueForge
//
//  AAC via AVAudioConverter (iOS provides a hardware/software AAC encoder).
//

import Foundation
import AVFoundation

final class AACEncoder: AudioCodec {
    let id: CodecID = .aac

    private var format: PCMFormat!
    private var converter: AVAudioConverter?
    private var decodeConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?

    func configure(format: PCMFormat, bitrate: Int) throws {
        self.format = format
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                       sampleRate: format.sampleRate,
                                       channels: AVAudioChannelCount(format.channels),
                                       interleaved: true) else {
            throw CodecError.unsupportedFormat("bad input format")
        }
        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channels,
            AVEncoderBitRateKey: bitrate
        ]
        guard let outFmt = AVAudioFormat(settings: outSettings) else {
            throw CodecError.unsupportedFormat("bad output format")
        }
        guard let conv = AVAudioConverter(from: inFmt, to: outFmt) else {
            throw CodecError.encodingFailed("cannot create converter")
        }
        conv.bitRate = bitrate
        // Reverse converter for decode (AAC -> PCM).
        guard let decConv = AVAudioConverter(from: outFmt, to: inFmt) else {
            throw CodecError.encodingFailed("cannot create decode converter")
        }
        self.decodeConverter = decConv
        self.inputFormat = inFmt
        self.outputFormat = outFmt
        self.converter = conv
    }

    func reset() {
        converter?.reset()
        decodeConverter?.reset()
    }

    func encode(pcm: Data) throws -> Data {
        guard let converter = converter, let inFmt = inputFormat, let outFmt = outputFormat else {
            throw CodecError.encodingFailed("not configured")
        }
        let bytesPerFrame = Int(inFmt.streamDescription.pointee.mBytesPerFrame)
        let frameCount = pcm.count / bytesPerFrame
        guard frameCount > 0 else { throw CodecError.encodingFailed("empty input") }

        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw CodecError.encodingFailed("alloc input")
        }
        inBuf.frameLength = AVAudioFrameCount(frameCount)
        pcm.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(inBuf.int16ChannelData![0], base, pcm.count)
            }
        }

        var error: NSError?
        var consumed = false
        let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(frameCount))!
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return inBuf
        }
        if let error = error { throw CodecError.encodingFailed(error.localizedDescription) }
        guard status == .haveData || status == .inputRanDry else {
            throw CodecError.encodingFailed("convert status \(status.rawValue)")
        }
        // Extract encoded bytes
        guard let ad = outBuf.audioBufferList.pointee.mBuffers.mData else {
            throw CodecError.encodingFailed("no output data")
        }
        let size = Int(outBuf.audioBufferList.pointee.mBuffers.mDataByteSize)
        return Data(bytes: ad, count: size)
    }

    func decode(frame: Data) throws -> Data {
        guard let converter = decodeConverter, let inFmt = inputFormat, let outFmt = outputFormat else {
            throw CodecError.decodingFailed("not configured")
        }
        guard !frame.isEmpty else { throw CodecError.decodingFailed("empty frame") }

        // Pack the compressed AAC frame into a compressed buffer.
        let srcBuf = AVAudioCompressedBuffer(format: outFmt, packetCapacity: 1,
                                            maximumPacketSize: frame.count)
        frame.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(srcBuf.data, base, frame.count)
            }
        }
        srcBuf.byteLength = UInt32(frame.count)
        srcBuf.packetCount = 1
        if let pd = srcBuf.packetDescriptions {
            pd.pointee = AudioStreamPacketDescription(mStartOffset: 0,
                                                     mVariableFramesInPacket: 0,
                                                     mDataByteSize: UInt32(frame.count))
        }

        // Estimate output capacity (AAC frames are typically 1024 samples).
        let capacity = AVAudioFrameCount(max(1024, Int(format!.sampleRate / 100.0)))
        guard let dstBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: capacity) else {
            throw CodecError.decodingFailed("alloc output buffer")
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: dstBuf, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return srcBuf
        }
        if let error = error { throw CodecError.decodingFailed(error.localizedDescription) }
        guard status == .haveData || status == .inputRanDry else {
            throw CodecError.decodingFailed("convert status \(status.rawValue)")
        }
        guard dstBuf.frameLength > 0 else {
            throw CodecError.decodingFailed("no decoded samples")
        }

        let bytesPerFrame = Int(inFmt.streamDescription.pointee.mBytesPerFrame)
        let byteCount = Int(dstBuf.frameLength) * bytesPerFrame
        guard let base = dstBuf.int16ChannelData?[0] else {
            throw CodecError.decodingFailed("no output data")
        }
        return Data(bytes: base, count: byteCount)
    }
}
