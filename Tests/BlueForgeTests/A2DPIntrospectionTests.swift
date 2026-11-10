import XCTest
@testable import BlueForge

final class A2DPIntrospectionTests: XCTestCase {

    func testPathFilterDetectsBluetoothContainers() {
        XCTAssertTrue(BluetoothPathFilter.isBluetoothRelated(
            "/var/containers/Data/System/ABC/Library/Preferences/com.apple.bluetooth.plist"))
        XCTAssertTrue(BluetoothPathFilter.isBluetoothRelated(
            "/var/containers/Shared/SystemGroup/systemgroup.com.apple.blued"))
        XCTAssertFalse(BluetoothPathFilter.isBluetoothRelated(
            "/var/containers/Data/System/ABC/Library/Preferences/com.apple.weather.plist"))
    }

    func testLooksLikePreferenceFile() {
        XCTAssertTrue(A2DPIntrospection.looksLikePreferenceFile(
            "Library/Preferences/com.apple.bluetooth.plist"))
        XCTAssertFalse(A2DPIntrospection.looksLikePreferenceFile(
            "Library/Preferences/com.apple.wifid.plist"))
    }

    func testPlistAnalysisSurfacesCodecSignals() throws {
        let plist: [String: Any] = [
            "com.apple.bluetooth.a2dp": [
                "codec.ldac.enabled": true,
                "codec.sbc.enabled": true,
                "unrelated": "value"
            ],
            "paired": [["name": "headphones", "a2dp": true]]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let lines = A2DPIntrospection.analyse(data: data, path: "com.apple.bluetooth.plist")
        let joined = lines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("ldac"), "expected ldac signal in: \(joined)")
        XCTAssertTrue(joined.contains("sbc"), "expected sbc signal in: \(joined)")
    }

    func testPlistAnalysisWithoutCodecKeywords() throws {
        let plist: [String: Any] = ["foo": "bar"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let lines = A2DPIntrospection.analyse(data: data, path: "x.plist")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("no codec keywords"))
    }

    func testTextAnalysisCountsCodecMentions() {
        let text = "aptx, aptx, aptx, ldac and LDAC"
        let data = Data(text.utf8)
        let lines = A2DPIntrospection.analyse(data: data, path: "config.txt")
        let joined = lines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("aptx ×3"))
        XCTAssertTrue(joined.contains("ldac ×2"))
    }

    func testFlattenRespectsDepthCap() {
        var deepest: [String: Any] = ["leaf": 1]
        for _ in 0..<10 {
            deepest = ["k": deepest]
        }
        let flat = A2DPIntrospection.flatten(deepest)
        XCTAssertTrue(flat.isEmpty || flat.values.allSatisfy { !$0.isEmpty })
    }

    func testCountOccurrences() {
        XCTAssertEqual(A2DPIntrospection.countOccurrences("aXbXb", "X"), 2)
        XCTAssertEqual(A2DPIntrospection.countOccurrences("aaaa", "aa"), 2)
        XCTAssertEqual(A2DPIntrospection.countOccurrences("", "x"), 0)
    }
}
