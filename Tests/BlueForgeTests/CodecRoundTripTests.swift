//
//  CodecRoundTripTests.swift
//  BlueForgeTests
//

import XCTest
@testable import BlueForge

final class CodecRoundTripTests: XCTestCase {

    func testSBCConfigure() throws {
        let c = SBCEncoder()
        try c.configure(format: PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16), bitrate: 320000)
        c.reset()
        let pcm = Data(repeating: 0, count: 16 * 8 * 2 * 2) // blocks*subbands*channels*2
        let frame = try c.encode(pcm: pcm)
        XCTAssertFalse(frame.isEmpty)
        XCTAssertGreaterThan(frame.count, 4)
    }

    func testAACConfigure() throws {
        let c = AACEncoder()
        try c.configure(format: PCMFormat(sampleRate: 44100, channels: 2, bitsPerSample: 16), bitrate: 256000)
        c.reset()
        // AAC encoder needs full frames; smoke test config only
        XCTAssertNotNil(c)
    }

    func testCodecManagerSelection() {
        let m = CodecManager()
        for id in CodecID.allCases {
            m.selected = id
            // AOSP-available codecs should configure without error.
            if id.aospAvailable {
                XCTAssertNil(m.lastError, "\(id) configured with error: \(m.lastError ?? "")")
            } else {
                // Proprietary codecs configure (UI can select) but encode is blocked.
                XCTAssertNotNil(m.current)
            }
        }
    }

    func testLDACThrowsNotImplemented() {
        let c = LDACCodec()
        try? c.configure(format: PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16), bitrate: 990000)
        XCTAssertThrowsError(try c.encode(pcm: Data(count: 1024)))
    }

    func testAptXThrowsLicensing() {
        let c = AptXFamilyCodec(id: .aptx)
        try? c.configure(format: PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16), bitrate: 352000)
        XCTAssertThrowsError(try c.encode(pcm: Data(count: 1024))) { err in
            XCTAssertTrue((err as? CodecError)?.errorDescription?.contains("Licensing") ?? false)
        }
    }
}
