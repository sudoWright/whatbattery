import XCTest
import WhatBatteryCore
@testable import WhatBatteryDarwinBackend

final class AccessoryBatteryReaderTests: XCTestCase {

    func testParsePercent() {
        XCTAssertEqual(AccessoryBatteryReader.parsePercent("69%"), 69)
        XCTAssertEqual(AccessoryBatteryReader.parsePercent("100 %"), 100)
        XCTAssertNil(AccessoryBatteryReader.parsePercent("n/a"))
    }

    func testParseSystemProfilerFixture() throws {
        let root = try root(from: fixture)
        let accessories = AccessoryBatteryReader.parseSystemProfiler(root)

        // 3 connected accessories; not_connected and iDevices (no minorType) excluded.
        XCTAssertEqual(accessories.count, 3)
        let byName = Dictionary(uniqueKeysWithValues: accessories.map { ($0.name, $0) })

        let pods = try XCTUnwrap(byName["Darryl’s AirPods"])
        XCTAssertEqual(pods.kind, .headphones)
        XCTAssertEqual(pods.cells, [.init(label: "Left", percent: 69), .init(label: "Right", percent: 75)])

        let keyboard = try XCTUnwrap(byName["Apple Wireless Keyboard"])
        XCTAssertEqual(keyboard.kind, .keyboard)
        XCTAssertTrue(keyboard.cells.isEmpty)   // no battery via system_profiler

        let mouse = try XCTUnwrap(byName["MX Anywhere 2"])
        XCTAssertEqual(mouse.kind, .mouse)
        XCTAssertFalse(mouse.isAvailable)

        XCTAssertNil(byName["WH-CH520"])         // not_connected, must be excluded
        XCTAssertNil(byName["iPhone"])           // no minorType, excluded
    }

    func testMergeFillsKeyboardFromIORegistryAndDeduplicates() throws {
        let sp = AccessoryBatteryReader.parseSystemProfiler(try root(from: fixture))
        let ioRegistry = [
            Accessory(
                id: Accessory.normalizeIdentifier("44:2A:60:EE:63:CC"),
                name: "Apple Wireless Keyboard", kind: .keyboard,
                cells: [.init(label: "", percent: 63)], transport: "Bluetooth"
            )
        ]
        let merged = AccessoryBatteryReader.merge(ioRegistry: ioRegistry, systemProfiler: sp)

        XCTAssertEqual(merged.count, 3)  // keyboard not duplicated

        let keyboard = try XCTUnwrap(merged.first { $0.kind == .keyboard })
        XCTAssertEqual(keyboard.cells, [.init(label: "", percent: 63)])  // filled from IORegistry

        let pods = try XCTUnwrap(merged.first { $0.kind == .headphones })
        XCTAssertEqual(pods.cells.count, 2)  // AirPods cells preserved
    }

    // MARK: - Helpers

    private func root(from json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private let fixture = """
    {
      "SPBluetoothDataType": [
        {
          "controller_properties": { "controller_address": "5C:9B:A6:82:B4:C9" },
          "device_connected": [
            { "Apple Wireless Keyboard": {
                "device_address": "44:2A:60:EE:63:CC",
                "device_minorType": "Keyboard" } },
            { "Darryl’s AirPods": {
                "device_address": "FC:A5:C8:C3:7E:C5",
                "device_batteryLevelLeft": "69%",
                "device_batteryLevelRight": "75%",
                "device_minorType": "Headphones" } },
            { "MX Anywhere 2": {
                "device_address": "EF:F5:6D:B4:F8:28",
                "device_minorType": "Mouse" } }
          ],
          "device_not_connected": [
            { "iPhone": { "device_address": "60:82:46:A1:49:6E" } },
            { "WH-CH520": {
                "device_address": "E8:9E:13:3B:03:18",
                "device_minorType": "Headset" } }
          ]
        }
      ]
    }
    """
}
