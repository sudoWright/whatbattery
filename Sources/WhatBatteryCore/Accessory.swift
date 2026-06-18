import Foundation

/// A connected Bluetooth accessory and whatever battery level macOS exposes for
/// it. Accessories only report a charge level (never health, cycles, or
/// capacity), and many third-party devices report nothing at all, so `cells`
/// can be empty (`isAvailable == false`), which the UI shows as a greyed
/// "battery unavailable" row.
public struct Accessory: Codable, Equatable, Sendable, Identifiable {
    /// Device category, used to pick an icon and group the list.
    public enum Kind: String, Codable, Sendable {
        case keyboard, mouse, trackpad, headphones, other

        /// Map a `system_profiler` `device_minorType` to a kind.
        public static func from(minorType: String?) -> Kind {
            switch (minorType ?? "").lowercased() {
            case "keyboard": return .keyboard
            case "mouse": return .mouse
            case "trackpad": return .trackpad
            case "headphones", "headset": return .headphones
            default: return .other
            }
        }
    }

    /// One battery cell. `label` is "" for a single combined level (input
    /// devices) or "Left" / "Right" / "Case" for multi-cell devices (AirPods).
    public struct Cell: Codable, Equatable, Sendable {
        public let label: String
        public let percent: Int

        public init(label: String, percent: Int) {
            self.label = label
            self.percent = percent
        }
    }

    /// Stable identifier (normalised Bluetooth address) so Pro history can track
    /// a specific device across sessions.
    public let id: String
    public let name: String
    public let kind: Kind
    public let cells: [Cell]
    public let transport: String?

    public init(id: String, name: String, kind: Kind, cells: [Cell], transport: String?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.cells = cells
        self.transport = transport
    }

    /// Whether macOS exposes any battery level for this accessory.
    public var isAvailable: Bool { !cells.isEmpty }

    /// The lowest cell, the headline figure (e.g. the emptier AirPod), or nil
    /// when no level is available.
    public var lowestPercent: Int? { cells.map(\.percent).min() }

    /// "63%" for a single combined level, or "L 69%  R 75%  Case 80%" for a
    /// multi-cell device. Empty string when no level is available.
    public var levelSummary: String {
        if cells.isEmpty { return "" }
        if cells.count == 1, cells[0].label.isEmpty { return "\(cells[0].percent)%" }
        return cells.map { cell in
            let tag: String
            switch cell.label {
            case "Left": tag = "L"
            case "Right": tag = "R"
            default: tag = cell.label
            }
            return "\(tag) \(cell.percent)%"
        }.joined(separator: "  ")
    }

    /// Normalise a Bluetooth address to a stable key: lowercase, no separators.
    /// IORegistry reports `44-2a-60-...`, system_profiler `44:2A:60:...`; both
    /// collapse to the same id.
    public static func normalizeIdentifier(_ raw: String) -> String {
        raw.lowercased().filter { $0 != ":" && $0 != "-" }
    }
}
