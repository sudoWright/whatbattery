import XCTest
@testable import WhatBatteryCore

final class AccessoryTests: XCTestCase {
    func testKindFromMinorType() {
        XCTAssertEqual(Accessory.Kind.from(minorType: "Keyboard"), .keyboard)
        XCTAssertEqual(Accessory.Kind.from(minorType: "Mouse"), .mouse)
        XCTAssertEqual(Accessory.Kind.from(minorType: "Trackpad"), .trackpad)
        XCTAssertEqual(Accessory.Kind.from(minorType: "Headphones"), .headphones)
        XCTAssertEqual(Accessory.Kind.from(minorType: "Headset"), .headphones)
        XCTAssertEqual(Accessory.Kind.from(minorType: nil), .other)
        XCTAssertEqual(Accessory.Kind.from(minorType: "Phone"), .other)
    }

    func testNormalizeIdentifierCollapsesSeparatorsAndCase() {
        XCTAssertEqual(Accessory.normalizeIdentifier("44:2A:60:EE:63:CC"), "442a60ee63cc")
        XCTAssertEqual(Accessory.normalizeIdentifier("44-2a-60-ee-63-cc"), "442a60ee63cc")
    }

    func testAvailabilityAndLowest() {
        let unavailable = Accessory(id: "x", name: "MX Anywhere 2", kind: .mouse, cells: [], transport: "Bluetooth")
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertNil(unavailable.lowestPercent)

        let pods = Accessory(
            id: "y", name: "AirPods", kind: .headphones,
            cells: [.init(label: "Left", percent: 69), .init(label: "Right", percent: 75)],
            transport: "Bluetooth"
        )
        XCTAssertTrue(pods.isAvailable)
        XCTAssertEqual(pods.lowestPercent, 69)
    }

    func testLevelSummary() {
        let single = Accessory(id: "a", name: "KB", kind: .keyboard, cells: [.init(label: "", percent: 63)], transport: nil)
        XCTAssertEqual(single.levelSummary, "63%")

        let pods = Accessory(id: "b", name: "AirPods", kind: .headphones,
            cells: [.init(label: "Left", percent: 69), .init(label: "Right", percent: 75), .init(label: "Case", percent: 80)], transport: nil)
        XCTAssertEqual(pods.levelSummary, "L 69%  R 75%  Case 80%")

        let none = Accessory(id: "c", name: "MX", kind: .mouse, cells: [], transport: nil)
        XCTAssertEqual(none.levelSummary, "")
    }

    func testCodableRoundTrip() throws {
        let pods = Accessory(
            id: "fca5c8c37ec5", name: "AirPods", kind: .headphones,
            cells: [.init(label: "Left", percent: 69), .init(label: "Right", percent: 75)],
            transport: "Bluetooth"
        )
        let data = try JSONEncoder().encode(pods)
        let decoded = try JSONDecoder().decode(Accessory.self, from: data)
        XCTAssertEqual(decoded, pods)
    }
}
