//
//  Codec.swift
//  BlueForge
//
//  Common abstraction for a Bluetooth audio codec.
//  A codec converts between PCM audio and a compressed bitstream.
//

import Foundation
import AVFoundation

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Supported Bluetooth audio codecs.
/// Note on jailed-iOS feasibility:
///   - AAC, SBC: implementable (AAC via AVAudioConverter, SBC via software encoder).
///   - LDAC, LC3 (LE Audio): reference C implementations exist in AOSP; bridge via
///     a C/Obj-C wrapper target (see AOSPBridge/).
///   - aptX / aptX HD / aptX LL / aptX Adaptive / aptX Lossless: proprietary
///     Qualcomm IP. NOT present in AOSP. Require a Qualcomm license + SDK.
///     Included here as stubs so the UI/manager can reason about them, but they
///     cannot be shipped in a jailed app without licensing.
enum CodecID: String, CaseIterable, Identifiable {
    case sbc = "SBC"
    case aac = "AAC"
    case ldac = "LDAC"
    case lc3 = "LC3"          // LE Audio
    case aptx = "aptX"
    case aptxHD = "aptX HD"
    case aptxLL = "aptX LL"
    case aptxAdaptive = "aptX Adaptive"
    case aptxLossless = "aptX Lossless"

    var id: String { rawValue }

    /// Whether this codec can be implemented from publicly available (AOSP) source.
    var aospAvailable: Bool {
        switch self {
        case .sbc, .aac, .ldac, .lc3: return true
        default: return false
        }
    }

    /// Whether iOS exposes a native encoder for this codec.
    var nativeIOSEncoder: Bool {
        switch self {
        case .aac: return true   // AVAudioConverter
        default: return false
        }
    }
}

/// PCM format produced/consumed by every codec.
struct PCMFormat {
    let sampleRate: Double      // e.g. 44100, 48000, 96000
    let channels: Int          // 1 or 2
    let bitsPerSample: Int     // 16 or 24
}

/// A codec instance. Implementations must be thread-safe for encode/decode calls
/// coming from the audio real-time thread; heavy work should be off the RT thread.
protocol AudioCodec {
    var id: CodecID { get }
    /// Configure for a given PCM format and target bitrate (bits/sec).
    func configure(format: PCMFormat, bitrate: Int) throws
    /// Encode a chunk of interleaved PCM (Int16/Int24) into a compressed frame.
    func encode(pcm: Data) throws -> Data
    /// Decode a compressed frame back to interleaved PCM.
    func decode(frame: Data) throws -> Data
    /// Reset internal state (e.g. on stream restart).
    func reset()
}

/// Static capability info for a codec.
struct CodecInfo {
    let id: CodecID
    let maxSampleRate: Int
    let maxBitrateKbps: Int
    let latencyMs: String
    let notes: String
}

extension CodecID {
    var info: CodecInfo {
        switch self {
        case .sbc: return CodecInfo(id: self, maxSampleRate: 48000, maxBitrateKbps: 345, latencyMs: "~3-4", notes: "Mandatory A2DP codec. AOSP reference available.")
        case .aac: return CodecInfo(id: self, maxSampleRate: 48000, maxBitrateKbps: 320, latencyMs: "~4-6", notes: "Native iOS encoder via AVAudioConverter.")
        case .ldac: return CodecInfo(id: self, maxSampleRate: 96000, maxBitrateKbps: 990, latencyMs: "~5-7", notes: "AOSP libldac. Bridge via AOSPBridge.")
        case .lc3: return CodecInfo(id: self, maxSampleRate: 48000, maxBitrateKbps: 384, latencyMs: "~7.5-10", notes: "LE Audio mandatory. AOSP liblc3.")
        case .aptx: return CodecInfo(id: self, maxSampleRate: 48000, maxBitrateKbps: 352, latencyMs: "~2", notes: "Qualcomm proprietary. License required.")
        case .aptxHD: return CodecInfo(id: self, maxSampleRate: 48000, maxBitrateKbps: 576, latencyMs: "~2", notes: "Qualcomm proprietary. License required.")
        case .aptxLL: return CodecInfo(id: self, maxSampleRate: 48000, maxBitrateKbps: 352, latencyMs: "~1.5", notes: "Qualcomm proprietary. License required.")
        case .aptxAdaptive: return CodecInfo(id: self, maxSampleRate: 96000, maxBitrateKbps: 420, latencyMs: "~2-80", notes: "Qualcomm proprietary. License required.")
        case .aptxLossless: return CodecInfo(id: self, maxSampleRate: 96000, maxBitrateKbps: 1200, latencyMs: "~2", notes: "Qualcomm proprietary. License required.")
        }
    }
}

/// Errors common to all codecs.
enum CodecError: Error, LocalizedError {
    case notImplemented(String)
    case unsupportedFormat(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case licensingRequired(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let m): return "Not implemented: \(m)"
        case .unsupportedFormat(let m): return "Unsupported format: \(m)"
        case .encodingFailed(let m): return "Encoding failed: \(m)"
        case .decodingFailed(let m): return "Decoding failed: \(m)"
        case .licensingRequired(let m): return "Licensing required: \(m)"
        }
    }
}
