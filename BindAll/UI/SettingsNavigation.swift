import SwiftUI

extension EnvironmentValues {
    /// Switches the Settings window to another tab, for "change it on the Shortcuts tab" links.
    @Entry var showSettingsTab: (SettingsTab) -> Void = { _ in }
}
