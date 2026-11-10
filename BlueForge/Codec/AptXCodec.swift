//
//  AptXCodec.swift
//  BlueForge
//
//  aptX / aptX HD / aptX LL / aptX Adaptive / aptX Lossless.
//  These are Qualcomm proprietary IP. They are NOT part of AOSP and cannot be
//  legally reimplemented from public sources. Shipping them in an app requires
//  a Qualcomm license + their SDK (e.g. aptX Adaptive SDK for OEMs).
//  We keep them in the codec table so the UI/manager can reason about them,
//  but encoding always throws .licensingRequired.
//

import Foundation

final class AptXFamilyCodec: AudioCodec {
    let id: CodecID
    init(id: CodecID) { self.id = id }

    private var format: PCMFormat!
    private var bitrate: Int = 0

    func configure(format: PCMFormat, bitrate: Int) throws {
        self.format = format
        self.bitrate = bitrate
    }

    func reset() { }

    func encode(pcm: Data) throws -> Data {
        throw CodecError.licensingRequired(
            "\(id.rawValue) is Qualcomm proprietary. Obtain a license and integrate the Qualcomm SDK.")
    }

    func decode(frame: Data) throws -> Data {
        throw CodecError.licensingRequired(
            "\(id.rawValue) is Qualcomm proprietary. Obtain a license and integrate the Qualcomm SDK.")
    }
}
