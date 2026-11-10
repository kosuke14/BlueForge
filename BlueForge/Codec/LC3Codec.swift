//
//  LC3Codec.swift
//  BlueForge
//
//  LC3 – Low Complexity Communication Codec, mandatory for LE Audio.
//  Reference implementation ships in AOSP (Android 13+):
//    external/liblc3/  (lc3_encoder, lc3_decoder)
//  Bridge via AOSPBridge/. Used for LE Audio (ISO) streaming.
//

import Foundation

final class LC3Codec: AudioCodec {
    let id: CodecID = .lc3

    private var format: PCMFormat!
    private var bitrate: Int = 0
    private var handle: UnsafeMutableRawPointer?

    func configure(format: PCMFormat, bitrate: Int) throws {
        // LC3 supports 8/16/24/32/44.1/48 kHz, 7.5/10 ms frames.
        self.format = format
        self.bitrate = bitrate
        // TODO: AOSPBridge.lc3Create(...)
    }

    func reset() { }

    func encode(pcm: Data) throws -> Data {
        throw CodecError.notImplemented("LC3 requires AOSPBridge (liblc3). See README.")
    }

    func decode(frame: Data) throws -> Data {
        throw CodecError.notImplemented("LC3 requires AOSPBridge (liblc3). See README.")
    }
}
