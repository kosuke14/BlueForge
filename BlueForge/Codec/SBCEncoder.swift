import Foundation

final class SBCEncoder: AudioCodec {
    let id: CodecID = .sbc

    private var format: PCMFormat!
    private var bitrate: Int = 0
    var ctx: OpaquePointer?

    func configure(format: PCMFormat, bitrate: Int) throws {
        guard format.channels == 1 || format.channels == 2 else {
            throw CodecError.unsupportedFormat("SBC supports 1 or 2 channels")
        }
        guard [16000,32000,44100,48000].contains(Int(format.sampleRate)) else {
            throw CodecError.unsupportedFormat("SBC sample rate not supported")
        }
        self.format = format
        self.bitrate = bitrate
        if let c = ctx { sbc_destroy(c); ctx = nil }
        let blocks = 16
        let subbands = 8
        let channelMode = format.channels == 1 ? 0 : 3
        let allocation = 1
        let bitpool = max(16, min(64, bitrate / (Int(format.sampleRate) * format.channels / 1000 * 4)))
        guard let c = sbc_create(Int32(format.sampleRate), Int32(format.channels),
                                 Int32(bitpool), Int32(blocks), Int32(subbands),
                                 Int32(allocation), Int32(channelMode)) else {
            throw CodecError.encodingFailed("sbc_create failed")
        }
        ctx = c
    }

    func reset() {
        if let c = ctx { sbc_destroy(c); ctx = nil }
        if let f = format {
            try? configure(format: f, bitrate: bitrate)
        }
    }

    func encode(pcm: Data) throws -> Data {
        guard let ctx = ctx else { throw CodecError.encodingFailed("not configured") }
        let cs = Int(sbc_codesize(ctx))
        guard pcm.count >= cs else {
            throw CodecError.encodingFailed("not enough PCM for a frame")
        }
        let fl = Int(sbc_frame_length(ctx))
        var buffer = [UInt8](repeating: 0, count: fl)
        let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
            guard let base = buf.baseAddress else { return -1 }
            return pcm.withUnsafeBytes { (pro: UnsafeRawBufferPointer) -> Int in
                guard let p = pro.baseAddress else { return -1 }
                return Int(sbc_encode_frame(ctx, p.assumingMemoryBound(to: Int16.self),
                                           Int32(pcm.count),
                                           base, Int32(fl)))
            }
        }
        guard n > 0 else { throw CodecError.encodingFailed("sbc encode failed") }
        return Data(buffer.prefix(n))
    }

    func decode(frame: Data) throws -> Data {
        guard let ctx = ctx else { throw CodecError.decodingFailed("not configured") }
        let cs = Int(sbc_codesize(ctx))
        var buffer = [UInt8](repeating: 0, count: cs)
        let n = frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return buffer.withUnsafeMutableBufferPointer { buf -> Int in
                guard let bp = buf.baseAddress else { return -1 }
                return Int(sbc_decode_frame(ctx, base.assumingMemoryBound(to: UInt8.self),
                                           Int32(frame.count),
                                           UnsafeMutableRawPointer(bp).assumingMemoryBound(to: Int16.self),
                                           Int32(cs)))
            }
        }
        guard n > 0 else { throw CodecError.decodingFailed("sbc decode failed") }
        return Data(buffer.prefix(n))
    }
}
