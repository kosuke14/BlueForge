//
//  CodecManager.swift
//  BlueForge
//

import Foundation
import Combine

/// Owns the set of available codecs and the currently selected one.
final class CodecManager: ObservableObject {
    @Published private(set) var available: [CodecID] = CodecID.allCases
    @Published var selected: CodecID = .aac {
        didSet { rebuildCodec() }
    }
    @Published private(set) var current: AudioCodec?
    @Published private(set) var lastError: String?

    var pcmFormat: PCMFormat { format }

    private var format: PCMFormat = PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16)
    private var bitrate: Int = 320_000

    func configure(format: PCMFormat, bitrate: Int) {
        self.format = format
        self.bitrate = bitrate
        rebuildCodec()
    }

    private func rebuildCodec() {
        do {
            let codec = try makeCodec(selected)
            try codec.configure(format: format, bitrate: bitrate)
            codec.reset()
            current = codec
            lastError = nil
        } catch {
            current = nil
            lastError = error.localizedDescription
        }
    }

    private func makeCodec(_ id: CodecID) throws -> AudioCodec {
        switch id {
        case .sbc: return SBCEncoder()
        case .aac: return AACEncoder()
        case .ldac: return LDACCodec()
        case .lc3: return LC3Codec()
        case .aptx, .aptxHD, .aptxLL, .aptxAdaptive, .aptxLossless:
            return AptXFamilyCodec(id: id)
        }
    }
}
