import XCTest
@testable import BlueForge

final class PLISTForgeTests: XCTestCase {

    private func sampleDict() -> [String: Any] {
        [
            "com.apple.bluetooth.a2dp": [
                "codec.ldac.enabled": true,
                "codec.sbc.enabled": true,
                "bitrate": 990,
                "deviceName": "headphones"
            ],
            "flavour": "prefer-lossless"
        ]
    }

    func testSetPathChangesNestedValue() throws {
        var dict = sampleDict()
        XCTAssertTrue(PLISTForge.setPath(&dict, path: ["com.apple.bluetooth.a2dp", "codec.ldac.enabled"], value: NSNumber(value: false)))
        let sub = dict["com.apple.bluetooth.a2dp"] as! [String: Any]
        XCTAssertEqual((sub["codec.ldac.enabled"] as! NSNumber).boolValue, false)
    }

    func testSetPathRejectsEmptyAndIndexPaths() {
        var dict = sampleDict()
        XCTAssertFalse(PLISTForge.setPath(&dict, path: [], value: NSNumber(value: 1)))
        XCTAssertFalse(PLISTForge.setPath(&dict, path: ["[3]"], value: NSNumber(value: 1)))
    }

    func testApplyChangesOnlyUntouchedKeys() throws {
        let root: Any = sampleDict()
        var mutable = root
        let edits = [
            ForgeKeyValue(components: ["com.apple.bluetooth.a2dp", "codec.ldac.enabled"], originalText: "true", editedText: "false"),
            ForgeKeyValue(components: ["com.apple.bluetooth.a2dp", "bitrate"], originalText: "990", editedText: "990"), // unchanged
            ForgeKeyValue(components: ["com.apple.bluetooth.a2dp", "[7]", "skip"], originalText: "x", editedText: "y") // index path skipped
        ]
        let changed = PLISTForge.apply(&mutable, edits: edits)
        XCTAssertEqual(changed.count, 1)
        let dict = mutable as! [String: Any]
        let sub = dict["com.apple.bluetooth.a2dp"] as! [String: Any]
        XCTAssertEqual((sub["codec.ldac.enabled"] as! NSNumber).boolValue, false)
        XCTAssertEqual((sub["bitrate"] as! NSNumber).intValue, 990)
    }

    func testRoundTripPreservesFormatAndValues() throws {
        let original = try PropertyListSerialization.data(fromPropertyList: sampleDict(), format: .binary, options: 0)
        let (root, format) = try PLISTForge.parse(original)
        XCTAssertEqual(format, .binary)
        var mutable = root
        _ = PLISTForge.apply(&mutable, edits: [
            ForgeKeyValue(components: ["flavour"], originalText: "prefer-lossless", editedText: "prefer-loudness")
        ])
        let out = try PLISTForge.serialise(mutable, format: format)
        let (reRoot, reFormat) = try PLISTForge.parse(out)
        XCTAssertEqual(reFormat, .binary)
        XCTAssertEqual((reRoot as! [String: Any])["flavour"] as! String, "prefer-loudness")
    }

    func testParseValueHeuristics() throws {
        XCTAssertEqual((PLISTForge.parseValue("true") as! NSNumber).boolValue, true)
        XCTAssertEqual((PLISTForge.parseValue("42") as! NSNumber).intValue, 42)
        XCTAssertEqual((PLISTForge.parseValue("9.5") as! NSNumber).doubleValue, 9.5, accuracy: 0.0001)
        XCTAssertEqual(PLISTForge.parseValue("stabby") as! String, "stabby")
        XCTAssertEqual((PLISTForge.parseValue(" 990 ") as! NSNumber).intValue, 990)
    }

    func testKeyValuesCodecOnlyFilter() throws {
        let (root, _) = try PLISTForge.parse(
            try PropertyListSerialization.data(fromPropertyList: sampleDict(), format: .xml, options: 0))
        let codecOnly = PLISTForge.keyValues(root: root, codecOnly: true)
        let all = PLISTForge.keyValues(root: root, codecOnly: false)
        XCTAssertTrue(codecOnly.count > 0)
        XCTAssertTrue(codecOnly.count < all.count)
        XCTAssertTrue(codecOnly.allSatisfy { $0.display.lowercased().contains("codec") || $0.display.lowercased().contains("lossless") })
    }
}
