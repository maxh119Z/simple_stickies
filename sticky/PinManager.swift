import AppKit
import Combine

// MARK: - FrontmostAppTracker
//
// Watches which app the user was on before activating us. When the user clicks
// the pin button on a sticky, we use this to know "the app you were just on".
//
// ObservableObject so SwiftUI views (the pin button) can re-render when the
// frontmost app changes — this is how the "tab-available" dot stays live.

final class FrontmostAppTracker: ObservableObject {
    static let shared = FrontmostAppTracker()

    @Published private(set) var currentApp: NSRunningApplication?
    @Published private(set) var previousApp: NSRunningApplication?

    /// Most recent non-self app. Prefers currentApp if it's non-self;
    /// otherwise falls back to previousApp.
    var lastNonSelf: NSRunningApplication? {
        let selfID = Bundle.main.bundleIdentifier
        if let c = currentApp, c.bundleIdentifier != selfID { return c }
        if let p = previousApp, p.bundleIdentifier != selfID { return p }
        return nil
    }

    private init() {
        if let current = NSWorkspace.shared.frontmostApplication {
            currentApp = current
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        previousApp = currentApp
        currentApp = app
    }
}

// MARK: - ChromeBridge

enum ChromeBridge {
    static let bundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev"
    ]

    static func isChrome(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return bundleIDs.contains(id)
    }

    static func currentTabURL() -> String? {
        let script = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                return URL of active tab of front window
            else
                return ""
            end if
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else {
            NSLog("StickyNotes: AppleScript compilation failed")
            return nil
        }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if let err = error {
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            let msg  = (err[NSAppleScript.errorMessage] as? String) ?? "(no message)"
            // -1743 = errAEEventNotPermitted (TCC denied)
            // -600  = procNotFound (Chrome not running)
            // -1712 = errAETimeout
            NSLog("StickyNotes: Chrome AppleScript error \(code): \(msg)")
            return nil
        }
        let url = result.stringValue ?? ""
        return url.isEmpty ? nil : url
    }
}

// MARK: - PinManager

final class PinManager {
    static let shared = PinManager()

    private struct Pin {
        weak var window: NSWindow?
        let bundleID: String
        let url: String?          // nil for app-only or .group mode
        let matchMode: PinMatchMode?  // .tab / .host / .group; nil = app-only
        let groupID: UUID?        // for .group mode
    }

    private var pins: [UUID: Pin] = [:]
    private var lastVisibility: [UUID: Bool] = [:]
    private var pendingHide: [UUID: DispatchWorkItem] = [:]

    /// Cached most-recent Chrome URL. Updated by polling while Chrome is frontmost
    /// and on app-activation transitions into Chrome. Never overwritten with nil
    /// (transient AppleScript failures preserve last-known value).
    private var lastSeenChromeURL: String?

    /// Public read-only access to the cached Chrome URL — for UI hints like
    /// "is the current tab already in this group?" that don't want to pay the
    /// AppleScript blocking cost just to render a checkmark.
    var lastChromeURL: String? { lastSeenChromeURL }

    private var pollTimer: Timer?
    private var observerInstalled = false

    // MARK: - Public API

    func pin(noteID: UUID, window: NSWindow, toAppBundleID bundleID: String,
             url: String? = nil, matchMode: PinMatchMode? = nil, groupID: UUID? = nil) {
        pins[noteID] = Pin(window: window, bundleID: bundleID, url: url,
                           matchMode: matchMode, groupID: groupID)
        lastVisibility[noteID] = nil
        installObserverIfNeeded()
        restartPollTimer()
        // Freshen the Chrome URL cache once on pin so first eval is accurate.
        if ChromeBridge.isChrome(bundleID), let u = ChromeBridge.currentTabURL() {
            lastSeenChromeURL = u
        }
        updateVisibility(for: noteID)
    }

    func unpin(noteID: UUID) {
        pendingHide[noteID]?.cancel()
        pendingHide[noteID] = nil
        if let window = pins[noteID]?.window {
            window.orderFront(nil)
        }
        pins.removeValue(forKey: noteID)
        lastVisibility.removeValue(forKey: noteID)
        restartPollTimer()
    }

    func isPinned(noteID: UUID) -> Bool { pins[noteID] != nil }

    // MARK: - Observers

    private func installObserverIfNeeded() {
        guard !observerInstalled else { return }
        observerInstalled = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(groupStoreChanged),
            name: .tabGroupStoreDidChange,
            object: nil
        )
    }

    @objc private func groupStoreChanged() {
        // A tab was added/removed from a group, or a group was renamed/deleted.
        // Re-evaluate every pinned note so .group-mode pins update immediately.
        for id in pins.keys { updateVisibility(for: id) }
    }

    @objc private func activeAppChanged() {
        // If pinned to Chrome and Chrome just became frontmost, freshen the URL.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if ChromeBridge.isChrome(front), hasURLPin {
            if let url = ChromeBridge.currentTabURL() {
                lastSeenChromeURL = url
            }
        }
        for id in pins.keys { updateVisibility(for: id) }
    }

    private var hasURLPin: Bool {
        pins.values.contains { $0.url != nil || $0.matchMode == .group }
    }

    private func restartPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard hasURLPin else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self else { return }
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            guard ChromeBridge.isChrome(front) else { return }
            // Skip update if URL hasn't actually changed — keeps things quiet.
            guard let url = ChromeBridge.currentTabURL() else { return }
            if url != self.lastSeenChromeURL {
                self.lastSeenChromeURL = url
                for id in self.pins.keys { self.updateVisibility(for: id) }
            }
        }
    }

    // MARK: - Visibility (debounced hide, no flicker on transients)

    private func updateVisibility(for noteID: UUID) {
        guard let pin = pins[noteID], let window = pin.window else {
            pins.removeValue(forKey: noteID)
            lastVisibility.removeValue(forKey: noteID)
            pendingHide[noteID]?.cancel()
            pendingHide[noteID] = nil
            return
        }
        let shouldShow = computeShouldShow(noteID: noteID)
        let currentlyShowing = lastVisibility[noteID] ?? true

        // No-op when state matches: cancel any pending hide and bail.
        if shouldShow == currentlyShowing {
            pendingHide[noteID]?.cancel()
            pendingHide[noteID] = nil
            return
        }

        if shouldShow {
            // Show immediately. Kill any pending hide.
            pendingHide[noteID]?.cancel()
            pendingHide[noteID] = nil
            window.orderFront(nil)
            lastVisibility[noteID] = true
        } else {
            // Schedule hide after a short delay. If state flips back to "show"
            // during the delay, the pending work gets cancelled — no flicker.
            pendingHide[noteID]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.commitHide(noteID)
            }
            pendingHide[noteID] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func commitHide(_ noteID: UUID) {
        guard let pin = pins[noteID], let window = pin.window else { return }
        // Recheck — state might have changed back during the 500ms.
        let shouldShow = computeShouldShow(noteID: noteID)
        if !shouldShow {
            window.orderOut(nil)
            lastVisibility[noteID] = false
        } else {
            // State flipped back; ensure visible.
            window.orderFront(nil)
            lastVisibility[noteID] = true
        }
        pendingHide[noteID] = nil
    }

    private func computeShouldShow(noteID: UUID) -> Bool {
        guard let pin = pins[noteID] else { return false }

        let realFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // When our own app is frontmost (user clicked/edited a sticky), evaluate
        // visibility against the app that was frontmost JUST BEFORE us. This
        // prevents the "click one sticky → every Chrome-pinned sticky pops into
        // view regardless of which tab the user was on" bug, while still
        // letting the user edit a pinned sticky without it disappearing.
        let effectiveFrontmost: String?
        if realFrontmost == Bundle.main.bundleIdentifier {
            if let last = FrontmostAppTracker.shared.lastNonSelf?.bundleIdentifier {
                effectiveFrontmost = last
            } else {
                // No record of a previous app (e.g. just-launched and no app
                // switch has occurred yet). Preserve whatever visibility the
                // note had last — don't reveal hidden notes, don't hide
                // visible ones. Default to true for brand-new pins.
                return lastVisibility[noteID] ?? true
            }
        } else {
            effectiveFrontmost = realFrontmost
        }

        guard effectiveFrontmost == pin.bundleID else { return false }

        // Group mode: check current Chrome URL against the group's URL set.
        if pin.matchMode == .group, let groupID = pin.groupID {
            guard ChromeBridge.isChrome(pin.bundleID) else { return false }
            guard let group = TabGroupStore.shared.group(id: groupID) else {
                // Group was deleted — hide the note.
                return false
            }
            let current = lastSeenChromeURL ?? ""
            return TabGroupStore.shared.contains(current, group: group)
        }

        // App-only pin — done.
        guard let pinURL = pin.url else { return true }
        // URL constraint only applies to Chrome.
        guard ChromeBridge.isChrome(pin.bundleID) else { return true }

        let current = lastSeenChromeURL ?? ""
        switch pin.matchMode ?? .tab {
        case .tab:
            return Self.canonicalURL(current) == Self.canonicalURL(pinURL)
        case .host:
            return Self.host(current) == Self.host(pinURL)
        case .group:
            return false  // handled above
        }
    }

    /// Strip everything after `?` or `#` so URLs with mutating query params and
    /// hash anchors still match the same logical "tab".
    private static func canonicalURL(_ url: String) -> String {
        var s = url
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if let h = s.firstIndex(of: "#") { s = String(s[..<h]) }
        return s
    }

    /// Extract host (e.g. "docs.google.com") from a URL string. Empty if invalid.
    private static func host(_ urlString: String) -> String {
        URL(string: urlString)?.host ?? ""
    }
}
