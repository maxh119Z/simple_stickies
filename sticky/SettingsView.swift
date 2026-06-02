import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var snippetStore = SnippetStore.shared

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
                LabeledContent("Peek at all notes") {
                    HotkeyRecorder(hotkey: $settings.revealAllHotkey)
                }
            } header: {
                Text("Global Shortcuts")
                    .font(.headline)
            } footer: {
                Text("Click a shortcut and press the key combo you want. Press Escape to cancel. \"Save note\" only fires when a sticky note is focused; the rest are global.\n\n\"Add Chrome tab to active group\" toggles the focused Chrome tab in or out of the active group.\n\n\"Peek at all notes\" reveals every pinned note at once so you can find and tidy them; press again to restore normal tab-based visibility. Closing (✕) a note while peeking hides it; use the trash button to delete it.")
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

            Section {
                if snippetStore.snippets.isEmpty {
                    Text("No snippets yet. Click \"Add Snippet\" to create one.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ForEach($snippetStore.snippets) { $snippet in
                        HStack(spacing: 8) {
                            TextField("trigger", text: $snippet.trigger)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            TextField("expansion (use $0 for cursor)",
                                      text: $snippet.expansion)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button {
                                snippetStore.remove(id: snippet.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete snippet")
                        }
                    }
                }
                Button {
                    snippetStore.add()
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Text Snippets")
                    .font(.headline)
            } footer: {
                Text("Type the trigger inside a sticky note, then press Tab to expand it. The trigger must be the last word before the cursor (no space after it). Use $0 in the expansion to mark where the cursor should land — e.g. \\frac{$0}{} puts the cursor between the first braces.\n\nExamples to try: alpha → \\alpha, frac → \\frac{$0}{}, sum → \\sum_{$0}^{}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
    }
}
