import AppKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var noteWindows: [UUID: NoteWindow] = [:]
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var groupsWindow: NSWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app — no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        // Force light appearance app-wide so notes always show the light pastel
        // colors, even when macOS is in dark mode. Delete this line to honor
        // the system appearance.
        NSApp.appearance = NSAppearance(named: .aqua)

        // Touch the FrontmostAppTracker so it starts observing app switches
        // immediately — its singleton init installs the workspace observer.
        _ = FrontmostAppTracker.shared

        setupStatusItem()

        // Wire up the settings store so changes re-register hotkeys.
        SettingsStore.shared.onHotkeyChange = { [weak self] in
            self?.registerHotkeys()
        }
        registerHotkeys()

        // Auto-open any pinned notes so the pin behavior is live immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            for note in NoteStore.shared.notes where note.pinnedToApp != nil {
                self?.showNote(note)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHistory()
        return true
    }

    // MARK: - Status bar item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "note.text",
                accessibilityDescription: "Sticky Notes"
            )
        }
        rebuildMenu()
    }

    /// Rebuild the menu so shortcut labels reflect the current settings.
    private func rebuildMenu() {
        let menu = NSMenu()
        let s = SettingsStore.shared

        menu.addItem(makeItem(
            "New Note  \(s.newNoteHotkey.displayString)",
            #selector(newNote)
        ))
        menu.addItem(makeItem(
            "Show History  \(s.historyHotkey.displayString)",
            #selector(showHistoryAction)
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            "Add Chrome Tab to Active Group  \(s.addTabToGroupHotkey.displayString)",
            #selector(toggleTabInActiveGroup)
        ))
        menu.addItem(makeItem("Manage Tab Groups…", #selector(showGroupsWindow)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(showSettings), key: ","))
        menu.addItem(makeItem("Test Chrome Pinning…", #selector(testChromePinning)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Sticky Notes",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        HotkeyManager.shared.unregisterAll()
        let s = SettingsStore.shared

        HotkeyManager.shared.register(
            keyCode: s.newNoteHotkey.keyCode,
            modifiers: s.newNoteHotkey.modifiers
        ) { [weak self] in
            self?.newNote()
        }

        HotkeyManager.shared.register(
            keyCode: s.historyHotkey.keyCode,
            modifiers: s.historyHotkey.modifiers
        ) { [weak self] in
            self?.toggleHistory()
        }

        HotkeyManager.shared.register(
            keyCode: s.addTabToGroupHotkey.keyCode,
            modifiers: s.addTabToGroupHotkey.modifiers
        ) { [weak self] in
            self?.toggleTabInActiveGroup()
        }

        rebuildMenu()
    }

    // MARK: - Actions

    @objc func newNote() {
        let note = Note(color: .random)
        NoteStore.shared.add(note)
        showNote(note)
    }

    @objc func showHistoryAction() {
        showHistory()
    }

    private func toggleHistory() {
        if let win = historyWindow, win.isVisible {
            win.close()
            historyWindow = nil
        } else {
            showHistory()
        }
    }

    @objc func testChromePinning() {
        let alert = NSAlert()
        alert.addButton(withTitle: "OK")
        if let url = ChromeBridge.currentTabURL() {
            alert.messageText = "Chrome integration is working ✓"
            alert.informativeText = """
            Active Chrome tab URL:
            \(url)

            Pin a note while focused on this tab and it will tab-track. \
            The pin button should show a green dot.
            """
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Chrome integration is NOT working"
            alert.informativeText = """
            The AppleScript call returned nothing. Open Console.app and search \
            for "StickyNotes" to see the exact error code.

            Most common causes:
              • TCC has a stale deny → run in Terminal:  tccutil reset AppleEvents
                then quit and relaunch this app
              • Hardened Runtime / App Sandbox blocking Apple Events without \
                the proper entitlement → remove these capabilities in Xcode's \
                Signing & Capabilities tab, or add the Apple Events entitlement
              • Chrome isn't actually running

            Diagnostic command (Terminal):
              codesign -d --entitlements - /Applications/sticky.app
              (or wherever the app is installed)
            """
            alert.alertStyle = .warning
        }
        alert.runModal()
    }

    @objc func showSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sticky Notes Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Settings window is always dark, regardless of the app-wide light appearance.
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showGroupsWindow() {
        NSLog("StickyNotes: showGroupsWindow invoked")
        if let win = groupsWindow {
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: GroupsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Tab Groups"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        // Raise above sticky-note windows (which are at .floating). Without
        // this, the Groups window opens behind any visible stickies and
        // appears not to open at all.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        // Match Settings: dark appearance overrides the app-wide light scheme.
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.delegate = self
        groupsWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Tab Group hotkey action

    /// Triggered by the global ⌃⌘N hotkey (default). Toggles the current Chrome
    /// tab in/out of the active tab group.
    @objc func toggleTabInActiveGroup() {
        let store = TabGroupStore.shared

        guard let url = ChromeBridge.currentTabURL() else {
            flashStatusBar(symbol: "exclamationmark.triangle", revertAfter: 1.2)
            NSLog("StickyNotes: ⌃⌘N pressed but no Chrome URL available (Chrome not running or not focused).")
            return
        }

        guard let activeID = store.activeGroupID, store.group(id: activeID) != nil else {
            // No active group → prompt the user once.
            let alert = NSAlert()
            alert.messageText = "No active tab group"
            alert.informativeText = "Create a group from a sticky note's right-click pin menu, or in Manage Groups, then this shortcut will add the current Chrome tab to it."
            alert.addButton(withTitle: "Manage Groups…")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                showGroupsWindow()
            }
            return
        }

        let added = store.toggleTab(url, in: activeID)
        flashStatusBar(symbol: added ? "checkmark.circle.fill" : "minus.circle.fill",
                       revertAfter: 0.9)
    }

    /// Briefly change the menu bar icon as feedback, then revert.
    private func flashStatusBar(symbol: String, revertAfter seconds: Double) {
        guard let button = statusItem.button else { return }
        let original = button.image
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.statusItem.button?.image = original
        }
    }

    // MARK: - Note windows

    func showNote(_ note: Note) {
        if let existing = noteWindows[note.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let initialFrame: NSRect? = {
            if let x = note.frameX, let y = note.frameY,
               let w = note.frameW, let h = note.frameH {
                return NSRect(x: x, y: y, width: w, height: h)
            }
            return nil
        }()

        let id = note.id
        let view = NoteView(
            note: note,
            onClose:         { [weak self] in self?.closeNote(id, save: true) },
            onDelete:        { [weak self] in self?.deleteNote(id) },
            onShowHistory:   { [weak self] in self?.showHistory() },
            onShowSettings:  { [weak self] in self?.showSettings() },
            onNewNote:       { [weak self] in self?.newNote() },
            onPin:           { [weak self] bundleID, url, matchMode, groupID in
                guard let self, let window = self.noteWindows[id] else { return }
                PinManager.shared.pin(
                    noteID: id,
                    window: window,
                    toAppBundleID: bundleID,
                    url: url,
                    matchMode: matchMode,
                    groupID: groupID
                )
            },
            onUnpin:         { PinManager.shared.unpin(noteID: id) }
        )

        let window = NoteWindow(noteID: id, rootView: view, initialFrame: initialFrame)
        if initialFrame == nil { window.center() }
        window.delegate = self
        noteWindows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Re-register pin if note was already pinned (e.g., on launch restore).
        if let bundleID = note.pinnedToApp {
            PinManager.shared.pin(
                noteID: id,
                window: window,
                toAppBundleID: bundleID,
                url: note.pinnedToURL,
                matchMode: note.pinMatchMode,
                groupID: note.pinnedGroupID
            )
        }
    }

    private func closeNote(_ id: UUID, save: Bool) {
        // Guard against re-entry: window.close() triggers windowWillClose,
        // which calls back into closeNote. Without this guard we recurse
        // until the stack overflows.
        guard let window = noteWindows[id] else { return }

        if save, var note = NoteStore.shared.note(for: id) {
            let f = window.frame
            note.frameX = f.origin.x
            note.frameY = f.origin.y
            note.frameW = f.size.width
            note.frameH = f.size.height
            NoteStore.shared.update(note)
        }

        // Remove from the dict BEFORE close() so the guard above catches the
        // re-entrant call from windowWillClose.
        noteWindows.removeValue(forKey: id)
        window.close()
    }

    private func deleteNote(_ id: UUID) {
        PinManager.shared.unpin(noteID: id)
        if let note = NoteStore.shared.note(for: id) {
            NoteStore.shared.delete(note)
        }
        closeNote(id, save: false)
    }

    func showHistory() {
        if let win = historyWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryView(
            onSelect: { [weak self] note in
                self?.showNote(note)
                self?.historyWindow?.close()
                self?.historyWindow = nil
            },
            onClose: { [weak self] in
                self?.historyWindow?.close()
                self?.historyWindow = nil
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.center()
        window.delegate = self

        historyWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === historyWindow {
            historyWindow = nil
            return
        }
        if window === settingsWindow {
            settingsWindow = nil
            return
        }
        if window === groupsWindow {
            groupsWindow = nil
            return
        }
        if let noteWindow = window as? NoteWindow {
            closeNote(noteWindow.noteID, save: true)
        }
    }
}
