//
//  LDACCodec.swift
//  BlueForge
//

import Foundation

final class LDACCodec: AudioCodec {
    let id: CodecID = .ldac

    private var format: PCMFormat!
    private var bitrate: Int = 0
    var ctx: UnsafeMutablePointer<LDACContext>?

    func configure(format: PCMFormat, bitrate: Int) throws {
        guard [44100, 48000, 88200, 96000].contains(Int(format.sampleRate)) else {
            throw CodecError.unsupportedFormat("LDAC sample rate")
        }
        guard format.channels == 1 || format.channels == 2 else {
            throw CodecError.unsupportedFormat("LDAC channels")
        }
        self.format = format
        self.bitrate = bitrate
        if let c = ctx { ldac_destroy(c); ctx = nil }
        guard let c = ldac_create(Int32(format.sampleRate), Int32(format.channels), Int32(bitrate)) else {
            throw CodecError.encodingFailed("ldac_create failed")
        }
        ctx = c
    }

    func reset() {
        if let c = ctx { ldac_destroy(c); ctx = nil }
        if let f = format { try? configure(format: f, bitrate: bitrate) }
    }

    func encode(pcm: Data) throws -> Data {
        guard let ctx = ctx else { throw CodecError.encodingFailed("not configured") }
        // LDAC emits one transport frame (2 LDAC frames) per call.
        let minBytes = 2 * 128 * (format?.channels ?? 2) * 2
        guard pcm.count >= minBytes else {
            throw CodecError.encodingFailed("LDAC needs at least 256 samples")
        }
        var buffer = [UInt8](repeating: 0, count: 2048)
        let n = pcm.withUnsafeBytes { pro -> Int in
            guard let p = pro.baseAddress else { return -1 }
            return buffer.withUnsafeMutableBufferPointer { buf -> Int in
                guard let b = buf.baseAddress else { return -1 }
                return Int(ldac_encode(ctx, p.assumingMemoryBound(to: Int16.self), Int32(pcm.count),
                                      b, Int32(buffer.count)))
            }
        }
        guard n > 0 else { throw CodecError.encodingFailed("ldac encode failed") }
        return Data(buffer.prefix(n))
    }

    func decode(frame: Data) throws -> Data {
        guard let ctx = ctx else { throw CodecError.decodingFailed("not configured") }
        let cs = 2 * 128 * (format?.channels ?? 2) * 2
        var buffer = [UInt8](repeating: 0, count: max(cs, 4096))
        let n = frame.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return buffer.withUnsafeMutableBufferPointer { buf -> Int in
                guard let bp = buf.baseAddress else { return -1 }
                return Int(ldac_decode(ctx, base.assumingMemoryBound(to: UInt8.self), Int32(frame.count),
                                      bp.assumingMemoryBound(to: Int16.self), Int32(buffer.count)))
            }
        }
        guard n > 0 else { throw CodecError.decodingFailed("ldac decode failed") }
        return Data(buffer.prefix(n))
    }
}
