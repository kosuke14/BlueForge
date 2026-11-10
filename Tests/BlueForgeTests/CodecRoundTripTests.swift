import XCTest
@testable import BlueForge

final class CodecRoundTripTests: XCTestCase {

    func testSBCConfigureAndRoundTrip() throws {
        let c = SBCEncoder()
        try c.configure(format: PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16), bitrate: 320000)
        c.reset()
        let cs = sbc_codesize(c.ctx!)
        let pcm = Data(repeating: 0, count: Int(cs))
        let frame = try c.encode(pcm: pcm)
        XCTAssertFalse(frame.isEmpty)
        let dec = try c.decode(frame: frame)
        XCTAssertEqual(dec.count, Int(cs))
    }

    func testAACConfigure() throws {
        let c = AACEncoder()
        try c.configure(format: PCMFormat(sampleRate: 44100, channels: 2, bitsPerSample: 16), bitrate: 256000)
        c.reset()
        XCTAssertNotNil(c)
    }

    func testCodecManagerSelection() {
        let m = CodecManager()
        for id in CodecID.allCases {
            m.selected = id
            if id.aospAvailable {
                XCTAssertNil(m.lastError, "\(id) configured with error: \(m.lastError ?? "")")
            } else {
                XCTAssertNotNil(m.current)
            }
        }
    }

    func testLDACRoundTrip() throws {
        let c = LDACCodec()
        try c.configure(format: PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16), bitrate: 990000)
        c.reset()
        let pcm = Data(repeating: 0, count: 2 * 128 * 2 * 2)
        let frame = try c.encode(pcm: pcm)
        XCTAssertFalse(frame.isEmpty)
        let dec = try c.decode(frame: frame)
        XCTAssertGreaterThan(dec.count, 0)
    }

    func testLC3RoundTrip() throws {
        let c = LC3Codec()
        try c.configure(format: PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16), bitrate: 128000)
        c.reset()
        let fs = Int(lc3_frame_samples_count(c.ctx!))
        let pcm = Data(repeating: 0, count: fs * 2 * 2)
        let frame = try c.encode(pcm: pcm)
        XCTAssertFalse(frame.isEmpty)
        let dec = try c.decode(frame: frame)
        XCTAssertGreaterThan(dec.count, 0)
    }

    func testAptXThrowsLicensing() {
        let c = AptXFamilyCodec(id: .aptx)
        try? c.configure(format: PCMFormat(sampleRate: 48000, channels: 2, bitsPerSample: 16), bitrate: 352000)
        XCTAssertThrowsError(try c.encode(pcm: Data(count: 1024))) { err in
            XCTAssertTrue((err as? CodecError)?.errorDescription?.contains("Licensing") ?? false)
        }
    }
}
