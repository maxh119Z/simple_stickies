import Foundation
import Combine
import Carbon.HIToolbox
import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Hotkey model

struct HotkeySetting: Codable, Equatable {
    var keyCode: Int      // Carbon virtual key code (e.g. kVK_ANSI_N)
    var modifiers: Int    // Carbon modifier mask (e.g. controlKey | shiftKey)

    var displayString: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey  != 0 { s += "⌥" }
        if modifiers & shiftKey   != 0 { s += "⇧" }
        if modifiers & cmdKey     != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    /// SwiftUI KeyEquivalent for use with .keyboardShortcut(_:modifiers:).
    /// NOTE: fully qualified as SwiftUI.KeyEquivalent because Carbon.HIToolbox
    /// (imported in this file for kVK_* constants) also defines a type with
    /// the same name, causing "ambiguous" build errors otherwise.
    var swiftUIKey: SwiftUI.KeyEquivalent {
        switch keyCode {
        case kVK_Return:     return .return
        case kVK_Tab:        return .tab
        case kVK_Space:      return .space
        case kVK_Escape:     return .escape
        case kVK_Delete:     return .delete
        default:
            let name = keyName(for: keyCode).lowercased()
            // Use a closure rather than `KeyEquivalent.init` directly — the
            // type has multiple inits (Character, plus protocol-derived ones)
            // so the bare .init reference is ambiguous.
            return name.first.map { SwiftUI.KeyEquivalent($0) } ?? "s"
        }
    }

    /// Same disambiguation: Carbon also defines EventModifiers (as UInt32).
    var swiftUIModifiers: SwiftUI.EventModifiers {
        var mods: SwiftUI.EventModifiers = []
        if modifiers & cmdKey     != 0 { mods.insert(.command) }
        if modifiers & shiftKey   != 0 { mods.insert(.shift) }
        if modifiers & optionKey  != 0 { mods.insert(.option) }
        if modifiers & controlKey != 0 { mods.insert(.control) }
        return mods
    }
}

// MARK: - Settings

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var newNoteHotkey: HotkeySetting {
        didSet {
            persist()
            onHotkeyChange?()
        }
    }

    @Published var historyHotkey: HotkeySetting {
        didSet {
            persist()
            onHotkeyChange?()
        }
    }

    /// Local-only shortcut (works inside a focused note, not global). Forces an
    /// immediate save and flashes a "Saved" toast. Doesn't trigger re-registering
    /// global hotkeys since it isn't one.
    @Published var saveHotkey: HotkeySetting {
        didSet { persist() }
    }

    /// Global hotkey: toggle the current Chrome tab in/out of the active tab group.
    @Published var addTabToGroupHotkey: HotkeySetting {
        didSet {
            persist()
            onHotkeyChange?()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Set by AppDelegate so the store can ask it to re-register hotkeys.
    var onHotkeyChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    private init() {
        // Defaults: ⌘N new note, ⌘⇧N history, ⌘S save, ⌃⌘N add tab to active group.
        let defaultNew     = HotkeySetting(keyCode: kVK_ANSI_N, modifiers: cmdKey)
        let defaultHistory = HotkeySetting(keyCode: kVK_ANSI_N, modifiers: cmdKey | shiftKey)
        let defaultSave    = HotkeySetting(keyCode: kVK_ANSI_S, modifiers: cmdKey)
        let defaultAddTab  = HotkeySetting(keyCode: kVK_ANSI_N, modifiers: cmdKey | controlKey)

        // One-time migration: anyone who saved Ctrl-based shortcuts under v1 gets
        // their shortcuts force-rebound to the new Cmd-based defaults. v3 adds the
        // tab-group hotkey default. After this the user's customizations (if any)
        // are preserved across launches.
        let storedVersion = UserDefaults.standard.integer(forKey: "settingsVersion")
        let currentVersion = 3

        if storedVersion < 2 {
            self.newNoteHotkey = defaultNew
            self.historyHotkey = defaultHistory
            self.saveHotkey    = defaultSave
            self.addTabToGroupHotkey = defaultAddTab
            let enc = JSONEncoder()
            if let d = try? enc.encode(defaultNew)     { UserDefaults.standard.set(d, forKey: "newNoteHotkey") }
            if let d = try? enc.encode(defaultHistory) { UserDefaults.standard.set(d, forKey: "historyHotkey") }
            if let d = try? enc.encode(defaultSave)    { UserDefaults.standard.set(d, forKey: "saveHotkey") }
            if let d = try? enc.encode(defaultAddTab)  { UserDefaults.standard.set(d, forKey: "addTabToGroupHotkey") }
            UserDefaults.standard.set(currentVersion, forKey: "settingsVersion")
        } else {
            self.newNoteHotkey       = Self.load(key: "newNoteHotkey",       defaultTo: defaultNew)
            self.historyHotkey       = Self.load(key: "historyHotkey",       defaultTo: defaultHistory)
            self.saveHotkey          = Self.load(key: "saveHotkey",          defaultTo: defaultSave)
            self.addTabToGroupHotkey = Self.load(key: "addTabToGroupHotkey", defaultTo: defaultAddTab)
            // Bump version so future migrations can run.
            if storedVersion < currentVersion {
                UserDefaults.standard.set(currentVersion, forKey: "settingsVersion")
            }
        }

        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func load(key: String, defaultTo fallback: HotkeySetting) -> HotkeySetting {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(HotkeySetting.self, from: data) else {
            return fallback
        }
        return decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(newNoteHotkey) {
            defaults.set(data, forKey: "newNoteHotkey")
        }
        if let data = try? JSONEncoder().encode(historyHotkey) {
            defaults.set(data, forKey: "historyHotkey")
        }
        if let data = try? JSONEncoder().encode(saveHotkey) {
            defaults.set(data, forKey: "saveHotkey")
        }
        if let data = try? JSONEncoder().encode(addTabToGroupHotkey) {
            defaults.set(data, forKey: "addTabToGroupHotkey")
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("StickyNotes: launch-at-login error: \(error.localizedDescription)")
            // Bounce back to actual system state so the toggle reflects reality.
            DispatchQueue.main.async {
                self.launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

// MARK: - Key name lookup

func keyName(for keyCode: Int) -> String {
    let map: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Escape: "⎋",
        kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",",
        kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`",
    ]
    return map[keyCode] ?? "?"
}

/// Convert Cocoa modifier flags (from NSEvent) to a Carbon modifier mask.
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
    var mods = 0
    if flags.contains(.command)  { mods |= cmdKey }
    if flags.contains(.option)   { mods |= optionKey }
    if flags.contains(.control)  { mods |= controlKey }
    if flags.contains(.shift)    { mods |= shiftKey }
    return mods
}
