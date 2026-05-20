import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("New note") {
                    HotkeyRecorder(hotkey: $settings.newNoteHotkey)
                }
                LabeledContent("Show history") {
                    HotkeyRecorder(hotkey: $settings.historyHotkey)
                }
                LabeledContent("Save note") {
                    HotkeyRecorder(hotkey: $settings.saveHotkey)
                }
                LabeledContent("Add Chrome tab to active group") {
                    HotkeyRecorder(hotkey: $settings.addTabToGroupHotkey)
                }
            } header: {
                Text("Global Shortcuts")
                    .font(.headline)
            } footer: {
                Text("Click a shortcut and press the key combo you want. Press Escape to cancel. \"Save note\" only fires when a sticky note is focused; the rest are global.\n\n\"Add Chrome tab to active group\" toggles the currently focused Chrome tab in or out of the active group. Set an active group from a sticky note's right-click pin menu, or from Manage Groups.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("General")
                    .font(.headline)
            } footer: {
                Text("Sticky Notes will start automatically when you log in to your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
    }
}
