import Foundation

/// How the menu bar shows accessory batteries: a single pinned device, or every
/// connected accessory side by side. Persisted as the raw string.
public enum MenuBarAccessoryMode: String, CaseIterable, Sendable {
    case one
    case all
}

/// UserDefaults keys shared by the Pro Settings UI (which writes them) and the
/// app's menu bar renderer (which reads them). Kept here in the free layer so the
/// renderer never has to reference any Pro symbol.
public enum MenuBarAccessoryDefaults {
    /// Master on/off for showing any accessory battery in the menu bar.
    public static let enabledKey = "menuBarAccessoryEnabled"
    /// `MenuBarAccessoryMode` raw value. Defaults to `.one` when unset.
    public static let modeKey = "menuBarAccessoryMode"
    /// The pinned accessory id (normalized Bluetooth address) for `.one` mode.
    public static let pinnedIdKey = "menuBarAccessoryId"

    public static func mode(_ defaults: UserDefaults = .standard) -> MenuBarAccessoryMode {
        MenuBarAccessoryMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .one
    }
}
