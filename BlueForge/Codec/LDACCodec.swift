//
//  LDACCodec.swift
//  BlueForge
//
//  LDAC (Sony, donated to AOSP). Reference implementation ships in AOSP:
//    external/libldac/  (encoder: libldacBT_enc, decoder: libldacBT_dec)
//  On iOS we bridge the C library via an Objective-C++ wrapper target
//  (see AOSPBridge/). This Swift type is the façade.
//

import Foundation

final class LDACCodec: AudioCodec {
    let id: CodecID = .ldac

    private var format: PCMFormat!
    private var bitrate: Int = 0
    // Opaque handle to the AOSP encoder instance.
    private var handle: UnsafeMutableRawPointer?

    func configure(format: PCMFormat, bitrate: Int) throws {
        guard [44100, 48000, 88200, 96000].contains(Int(format.sampleRate)) else {
            throw CodecError.unsupportedFormat("LDAC sample rate")
        }
        self.format = format
        self.bitrate = bitrate
        // TODO: call ldacBT_get_handle / ldacBT_init_handle via AOSPBridge.
        // handle = AOSPBridge.ldacCreate(sampleRate:..., channels:..., bitrate:...)
    }

    func reset() {
        // TODO: AOSPBridge.ldacReset(handle)
    }

    func encode(pcm: Data) throws -> Data {
        guard handle != nil else {
            throw CodecError.notImplemented("LDAC requires AOSPBridge (libldac). See README.")
        }
        // TODO: AOSPBridge.ldacEncode(handle, pcm) -> Data
        throw CodecError.notImplemented("LDAC encode via AOSPBridge")
    }

    func decode(frame: Data) throws -> Data {
        throw CodecError.notImplemented("LDAC decode via AOSPBridge")
    }
}
