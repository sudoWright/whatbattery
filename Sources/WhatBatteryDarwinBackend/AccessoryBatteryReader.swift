import Foundation
import IOKit
import WhatBatteryCore

/// Reads Bluetooth accessory battery levels from the two places macOS exposes
/// them, and merges them into one list:
///
///  1. **IORegistry `BatteryPercent`** - Apple input devices (Magic Keyboard /
///     Mouse / Trackpad) report a single percentage here.
///  2. **`system_profiler SPBluetoothDataType -json`** - AirPods report
///     per-cell (Left / Right / Case) here, and it lists every connected
///     accessory (so third-party devices that report no battery still appear,
///     as `unavailable`).
///
/// `readAll()` does blocking I/O (a `system_profiler` subprocess), so call it
/// off the main actor on a slow cadence. The parse and merge steps are pure and
/// unit-tested from a captured fixture.
public enum AccessoryBatteryReader {

    // MARK: - Public entry point

    public static func readAll() -> [Accessory] {
        let fromSystemProfiler = runSystemProfiler().map(parseSystemProfiler) ?? []
        let fromIORegistry = readIORegistry()
        return merge(ioRegistry: fromIORegistry, systemProfiler: fromSystemProfiler)
    }

    // MARK: - Merge (pure)

    /// Combine the two sources by accessory id. system_profiler is the source of
    /// truth for the device set and names; IORegistry fills in the battery level
    /// for input devices that system_profiler lists without one (the keyboard).
    public static func merge(ioRegistry: [Accessory], systemProfiler: [Accessory]) -> [Accessory] {
        var byID: [String: Accessory] = [:]
        for accessory in systemProfiler { byID[accessory.id] = accessory }

        for accessory in ioRegistry {
            if let existing = byID[accessory.id] {
                // Keep the friendlier system_profiler name/kind; take its cells
                // when it has them (AirPods), otherwise fall back to IORegistry.
                let cells = existing.cells.isEmpty ? accessory.cells : existing.cells
                byID[accessory.id] = Accessory(
                    id: existing.id,
                    name: existing.name,
                    kind: existing.kind,
                    cells: cells,
                    transport: existing.transport ?? accessory.transport
                )
            } else {
                byID[accessory.id] = accessory
            }
        }

        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - system_profiler (parse is pure)

    /// Parse `system_profiler SPBluetoothDataType -json` output. Returns only
    /// recognised accessories (keyboard / mouse / trackpad / headphones); iPhones,
    /// iPads, and Macs carry no accessory `device_minorType` and are dropped.
    public static func parseSystemProfiler(_ root: [String: Any]) -> [Accessory] {
        guard let blocks = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        // label -> system_profiler key. "" is a single combined level.
        let cellKeys: [(String, String)] = [
            ("", "device_batteryLevelMain"),
            ("Left", "device_batteryLevelLeft"),
            ("Right", "device_batteryLevelRight"),
            ("Case", "device_batteryLevelCase"),
        ]

        var result: [Accessory] = []
        var seen = Set<String>()

        for block in blocks {
            // Match "device_connected" but not "device_not_connected".
            for (key, value) in block
            where key.lowercased().contains("connected") && !key.lowercased().contains("not_connected") {
                guard let devices = value as? [[String: Any]] else { continue }
                for wrapper in devices {
                    for (name, raw) in wrapper {
                        guard let info = raw as? [String: Any],
                              let address = info["device_address"] as? String else { continue }
                        let kind = Accessory.Kind.from(minorType: info["device_minorType"] as? String)
                        guard kind != .other else { continue }

                        let id = Accessory.normalizeIdentifier(address)
                        guard !seen.contains(id) else { continue }
                        seen.insert(id)

                        let cells = cellKeys.compactMap { label, profilerKey -> Accessory.Cell? in
                            guard let raw = info[profilerKey] as? String,
                                  let percent = parsePercent(raw) else { return nil }
                            return Accessory.Cell(label: label, percent: percent)
                        }
                        result.append(Accessory(id: id, name: name, kind: kind, cells: cells, transport: "Bluetooth"))
                    }
                }
            }
        }
        return result
    }

    /// "78%" -> 78. Tolerates stray whitespace.
    static func parsePercent(_ raw: String) -> Int? {
        Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    private static func runSystemProfiler() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Read off-thread so a wedged Bluetooth stack can't hang us forever; give
        // up after 5s and terminate the subprocess (matches BatteryConditionReader).
        let handle = pipe.fileHandleForReading
        let box = DataBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.data = handle.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return (try? JSONSerialization.jsonObject(with: box.data)) as? [String: Any]
    }

    // MARK: - IORegistry

    private static func readIORegistry() -> [Accessory] {
        var result: [Accessory] = []
        var seen = Set<String>()

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, "IOService",
                IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return result }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let props = properties(of: entry),
               let percent = props["BatteryPercent"] as? Int,
               let address = props["DeviceAddress"] as? String {
                let id = Accessory.normalizeIdentifier(address)
                if !seen.contains(id) {
                    seen.insert(id)
                    result.append(Accessory(
                        id: id,
                        name: (props["Product"] as? String) ?? "Bluetooth device",
                        kind: hidKind(usagePage: props["PrimaryUsagePage"] as? Int, usage: props["PrimaryUsage"] as? Int),
                        cells: [Accessory.Cell(label: "", percent: percent)],
                        transport: props["Transport"] as? String
                    ))
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return result
    }

    private static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    /// Classify an Apple input device from its HID usage (Generic Desktop page
    /// 0x01: keyboard = 6, mouse = 2; digitizer page 0x0D = trackpad).
    private static func hidKind(usagePage: Int?, usage: Int?) -> Accessory.Kind {
        switch (usagePage, usage) {
        case (0x01, 6): return .keyboard
        case (0x01, 2): return .mouse
        case (0x0D, _): return .trackpad
        default: return .other
        }
    }
}

/// A minimal box so the background read can hand the data back across the
/// semaphore (which provides the happens-before ordering).
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
