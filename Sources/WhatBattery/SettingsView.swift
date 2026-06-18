import SwiftUI
import WhatBatteryAppKit

/// App settings plus any plugin-contributed sections (the Pro licence section,
/// notifications later). Grows over time (history retention, menu bar badge,
/// launch at login).
struct SettingsView: View {
    @AppStorage("temperatureUnit") private var temperatureUnit = "C"
    /// When embedded in the menu bar popover, drop the fixed window frame and let
    /// the content size to the popover.
    var embedded = false
    /// Height to give the embedded form, so it matches the popover (which is
    /// sized by the accessory list) and scrolls internally rather than clipping.
    var embeddedHeight: CGFloat = 340

    var body: some View {
        Form {
            Picker("Temperature", selection: $temperatureUnit) {
                Text("Celsius (C)").tag("C")
                Text("Fahrenheit (F)").tag("F")
            }
            .pickerStyle(.inline)

            ForEach(Array(PluginRegistry.shared.settingsSections.enumerated()), id: \.offset) { _, build in
                build()
            }
        }
        .formStyle(.grouped)
        // Embedded in the popover: a bounded height that gives the settings room
        // and lets the grouped form scroll if the sections overflow.
        .frame(width: embedded ? nil : 360, height: embedded ? embeddedHeight : 280)
    }
}
