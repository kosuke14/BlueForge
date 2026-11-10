//
//  LC3Codec.swift
//  BlueForge
//

import Foundation

final class LC3Codec: AudioCodec {
    let id: CodecID = .lc3

    private var format: PCMFormat!
    private var bitrate: Int = 0
    var ctx: OpaquePointer?

    var pcmFrameBytes: Int {
        guard let ctx = ctx else { return 0 }
        return Int(lc3_frame_samples_count(ctx)) * (format?.channels ?? 1) * 2
    }

    func configure(format: PCMFormat, bitrate: Int) throws {
        let sr = Int(format.sampleRate)
        guard [8000,16000,24000,32000,48000].contains(sr) else {
            throw CodecError.unsupportedFormat("LC3 sample rate")
        }
        guard format.channels == 1 || format.channels == 2 else {
            throw CodecError.unsupportedFormat("LC3 channels")
        }
        self.format = format
        self.bitrate = bitrate
        if let c = ctx { lc3_destroy(c); ctx = nil }
        guard let c = lc3_create(Int32(sr), Int32(format.channels), Int32(bitrate), 10000) else {
            throw CodecError.encodingFailed("lc3_create failed")
        }
        ctx = c
    }

    func reset() { }

    func encode(pcm: Data) throws -> Data {
        guard let ctx = ctx else { throw CodecError.encodingFailed("not configured") }
        let fs = Int(lc3_frame_samples_count(ctx))
        let channels = format?.channels ?? 1
        let minBytes = fs * channels * 2
        guard pcm.count >= minBytes else {
            throw CodecError.encodingFailed("LC3 needs a full frame")
        }
        var buffer = [UInt8](repeating: 0, count: max(1024, minBytes))
        // ensure enough capacity: total frame block bytes unknown; use generous buffer
        buffer = [UInt8](repeating: 0, count: 4096)
        let n = pcm.withUnsafeBytes { (pro: UnsafeRawBufferPointer) -> Int in
            guard let p = pro.baseAddress else { return -1 }
            return buffer.withUnsafeMutableBufferPointer { buf -> Int in
                guard let b = buf.baseAddress else { return -1 }
                return Int(lc3_encode_frame(ctx, p.assumingMemoryBound(to: Int16.self), Int32(pcm.count),
                                          b, Int32(buf.count)))
            }
        }
        guard n > 0 else { throw CodecError.encodingFailed("lc3 encode failed") }
        return Data(buffer.prefix(n))
    }

    func decode(frame: Data) throws -> Data {
        guard let ctx = ctx else { throw CodecError.decodingFailed("not configured") }
        let fs = Int(lc3_frame_samples_count(ctx))
        let channels = format?.channels ?? 1
        let outBytes = fs * channels * 2
        var buffer = [UInt8](repeating: 0, count: max(outBytes, 4096))
        let n = frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return buffer.withUnsafeMutableBufferPointer { buf -> Int in
                guard let bp = buf.baseAddress else { return -1 }
                return Int(lc3_decode_frame(ctx, base.assumingMemoryBound(to: UInt8.self), Int32(frame.count),
                                           UnsafeMutableRawPointer(bp).assumingMemoryBound(to: Int16.self), Int32(buf.count)))
            }
        }
        guard n > 0 else { throw CodecError.decodingFailed("lc3 decode failed") }
        return Data(buffer.prefix(n))
    }
}
