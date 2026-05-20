import SwiftUI
import AppKit

struct NoteView: View {
    @State var note: Note
    var onClose: () -> Void
    var onDelete: () -> Void
    var onShowHistory: () -> Void
    var onShowSettings: () -> Void
    var onNewNote: () -> Void
    var onPin: (String, String?, PinMatchMode?, UUID?) -> Void   // bundleID, url, mode, groupID
    var onUnpin: () -> Void

    @State private var attributedText: NSAttributedString
    @State private var showSavedToast = false
    @State private var pinFeedback: String?
    @State private var isDrawing = false
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var frontmost = FrontmostAppTracker.shared
    @ObservedObject private var groupStore = TabGroupStore.shared

    private var store: NoteStore { NoteStore.shared }

    init(
        note: Note,
        onClose: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onShowHistory: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onNewNote: @escaping () -> Void,
        onPin: @escaping (String, String?, PinMatchMode?, UUID?) -> Void,
        onUnpin: @escaping () -> Void
    ) {
        self.note = note
        self.onClose = onClose
        self.onDelete = onDelete
        self.onShowHistory = onShowHistory
        self.onShowSettings = onShowSettings
        self.onNewNote = onNewNote
        self.onPin = onPin
        self.onUnpin = onUnpin

        let attr: NSAttributedString
        if let data = note.contentRTFD,
           let decoded = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil) {
            attr = decoded
        } else {
            let m = NSMutableAttributedString(string: note.content)
            m.addAttributes([
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.black
            ], range: NSRange(location: 0, length: m.length))
            attr = m
        }
        self._attributedText = State(initialValue: attr)
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor

            RichTextEditor(
                attributedText: $attributedText,
                highlightColor: highlightNSColor,
                defaultTextColor: .black,
                onTextChange: persistContent
            )
            .padding(.horizontal, 12)
            .padding(.top, 36)
            .padding(.bottom, 12)

            // Drawing layer — pure SwiftUI Canvas. When isDrawing is false,
            // `.allowsHitTesting(false)` makes clicks pass through to the text
            // editor below; when true, the canvas captures drags as strokes.
            // This replaces the NSViewRepresentable approach which had
            // hit-test races with NSHostingView.
            DrawingOverlay(
                strokes: $note.strokes,
                isDrawing: $isDrawing
            )
            .padding(.top, 36)   // keep header area clear so buttons stay clickable
            .onChange(of: note.strokes) { _ in
                store.update(note)
            }

            // Header
            HStack(spacing: 6) {
                optionsButton
                newNoteButton
                drawToggleButton
                Spacer()
                pinButton
                deleteButton
                closeButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
        )
        .overlay(alignment: .bottom) { bottomToast }
        .background(
            Button("Save") { flushSave() }
                .keyboardShortcut(settings.saveHotkey.swiftUIKey,
                                  modifiers: settings.saveHotkey.swiftUIModifiers)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .animation(.easeInOut(duration: 0.25), value: note.color)
        .contextMenu { menuContents }
    }

    // MARK: - Toast at bottom (shared by save + pin feedback)

    @ViewBuilder
    private var bottomToast: some View {
        if let msg = pinFeedback {
            toastPill(msg)
        } else if showSavedToast {
            toastPill("Saved")
        }
    }

    private func toastPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
            .padding(.bottom, 14)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        Color(hex: note.color.hex.light)
    }

    private var highlightNSColor: NSColor {
        NSColor(hexString: note.color.highlightHex).withAlphaComponent(0.55)
    }

    // MARK: - Buttons

    private func pillIcon(_ name: String, filled: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(filled ? .white : .black.opacity(0.72))
            .frame(width: 20, height: 20)
            .background(Circle().fill(filled ? Color.black.opacity(0.75) : Color.white))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 0.5)
    }

    /// Wraps pillIcon with a small green dot badge — used to indicate active
    /// tab-specific tracking on the pin button.
    private func pillIconWithBadge(_ name: String, filled: Bool, hasBadge: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            pillIcon(name, filled: filled)
            if hasBadge {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.2))
                    .offset(x: 3, y: -2)
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) { pillIcon("xmark") }
            .buttonStyle(.plain)
            .help("Close note")
    }

    private var optionsButton: some View {
        Menu { menuContents } label: { pillIcon("ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Options")
    }

    private var newNoteButton: some View {
        Button(action: onNewNote) { pillIcon("plus") }
            .buttonStyle(.plain)
            .help("New note")
    }

    private var drawToggleButton: some View {
        Button {
            isDrawing.toggle()
        } label: {
            pillIcon(isDrawing ? "scribble.variable" : "pencil.tip", filled: isDrawing)
        }
        .buttonStyle(.plain)
        .help(isDrawing ? "Stop drawing" : "Draw on this note")
    }

    private var deleteButton: some View {
        Button(action: onDelete) { pillIcon("trash") }
            .buttonStyle(.plain)
            .help("Delete note")
    }

    private var pinButton: some View {
        Button(action: togglePin) {
            pillIconWithBadge(
                note.pinnedToApp != nil ? "pin.fill" : "pin",
                filled: note.pinnedToApp != nil,
                hasBadge: chromeTabContextActive
            )
        }
        .buttonStyle(.plain)
        .help(pinTooltip)
        .contextMenu { pinContextMenuItems }
        // Force SwiftUI to re-create the button when pin state changes. Belt
        // and suspenders for any state-diffing edge case that might keep the
        // old icon visible after pinning.
        .id("pin-\(note.pinnedToApp ?? "none")-\(note.pinnedGroupID?.uuidString ?? "none")")
    }

    @ViewBuilder
    private var pinContextMenuItems: some View {
        let candidate = bestPinCandidate()
        let isChrome = ChromeBridge.isChrome(candidate?.bundleIdentifier)

        if let app = candidate, let bundleID = app.bundleIdentifier {
            let appName = app.localizedName ?? "this app"

            if isChrome {
                // URL is fetched at action time (inside the closures) so the menu
                // itself opens instantly without a blocking AppleScript call.
                Button("Pin to this tab") {
                    let url = ChromeBridge.currentTabURL()
                    pinTo(bundleID: bundleID,
                          url: url,
                          mode: url != nil ? .tab : nil,
                          groupID: nil,
                          appName: appName)
                }
                Button("Pin to Chrome (any tab)") {
                    pinTo(bundleID: bundleID, url: nil, mode: nil,
                          groupID: nil, appName: appName)
                }

                Divider()

                Menu("Pin to group") {
                    Button("+ New group from this tab…") {
                        createGroupAndPin(bundleID: bundleID, appName: appName)
                    }
                    if !groupStore.groups.isEmpty {
                        Divider()
                        ForEach(groupStore.groups) { group in
                            let active = groupStore.activeGroupID == group.id
                            Button("\(active ? "★ " : "  ")\(group.name)  (\(group.urls.count) tab\(group.urls.count == 1 ? "" : "s"))") {
                                pinTo(bundleID: bundleID, url: nil, mode: .group,
                                      groupID: group.id, appName: appName)
                            }
                        }
                    }
                }

                if !groupStore.groups.isEmpty {
                    // Cached URL (from PinManager) used only for the ✓ hint —
                    // doesn't block. Toggle action fetches a fresh URL.
                    let cachedURL = PinManager.shared.lastChromeURL
                    Menu("Add tab to group") {
                        ForEach(groupStore.groups) { group in
                            let inGroup = cachedURL
                                .flatMap { groupStore.contains($0, group: group) } ?? false
                            Button(inGroup ? "✓ \(group.name)  (tap to remove)" : group.name) {
                                if let url = ChromeBridge.currentTabURL() {
                                    let nowIn = groupStore.toggleTab(url, in: group.id)
                                    showPinFeedback(nowIn
                                        ? "Added to \(group.name)"
                                        : "Removed from \(group.name)")
                                }
                            }
                        }
                    }
                }
            } else {
                Button("Pin to \(appName)") {
                    pinTo(bundleID: bundleID, url: nil, mode: nil,
                          groupID: nil, appName: appName)
                }
            }
        } else {
            Text("Focus the app/tab you want first")
        }

        Divider()
        Button("Manage groups…") {
            NSLog("StickyNotes: ⊕ note context-menu 'Manage groups…' tapped")
            // Prefer the static shared (set in applicationDidFinishLaunching).
            // Fall back to NSApp.delegate cast in case the shared wasn't set
            // for some reason.
            if let d = AppDelegate.shared {
                NSLog("StickyNotes:   using AppDelegate.shared")
                d.showGroupsWindow()
            } else if let d = NSApp.delegate as? AppDelegate {
                NSLog("StickyNotes:   using NSApp.delegate fallback")
                d.showGroupsWindow()
            } else {
                NSLog("StickyNotes:   ✗ no AppDelegate available (this should be impossible)")
            }
        }

        if note.pinnedToApp != nil {
            Divider()
            Button(role: .destructive) {
                unpinNote()
            } label: {
                Text("Unpin")
            }
        }
    }

    private func createGroupAndPin(bundleID: String, appName: String) {
        let alert = NSAlert()
        alert.messageText = "New Tab Group"
        alert.informativeText = "Name your group. The current Chrome tab will be added, and this note will be pinned to the group."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "e.g. Project Alpha"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let group = groupStore.create(name: name)
        if let url = ChromeBridge.currentTabURL() {
            groupStore.addTab(url, to: group.id)
        }
        pinTo(bundleID: bundleID, url: nil, mode: .group, groupID: group.id, appName: appName)
    }

    /// Dot is visible when "tab-specific Chrome pinning is in play":
    /// - Not yet pinned: would clicking pin right now result in tab tracking?
    ///   (i.e., the focused app is Chrome)
    /// - Already pinned: did we successfully capture a tab URL?
    private var chromeTabContextActive: Bool {
        if note.pinnedToApp != nil {
            return note.pinnedToURL != nil
        }
        return ChromeBridge.isChrome(bestPinCandidate()?.bundleIdentifier)
    }

    private var pinTooltip: String {
        guard let bundleID = note.pinnedToApp else {
            if chromeTabContextActive {
                return "Click to pin to this Chrome tab"
            }
            return "Pin to current window — focus the app/tab first, then click this"
        }
        let appName = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        if let url = note.pinnedToURL {
            return "Pinned to \(appName) tab (green dot = tab tracking active):\n\(url)"
        }
        if ChromeBridge.isChrome(bundleID) {
            return "Pinned to \(appName) (app-level only — Apple Events permission needed for tab pinning)"
        }
        return "Pinned to \(appName) — click to unpin"
    }

    // MARK: - Pin actions

    /// Left-click default: pin to the focused app's current state.
    /// For Chrome that means the current tab (mode = .tab). For other apps,
    /// app-level only.
    private func togglePin() {
        if note.pinnedToApp != nil {
            unpinNote()
            return
        }
        guard let app = bestPinCandidate(), let bundleID = app.bundleIdentifier else {
            showPinFeedback("Switch to the app/tab you want, then come back and click pin")
            return
        }
        let url: String? = ChromeBridge.isChrome(bundleID)
            ? ChromeBridge.currentTabURL()
            : nil
        let mode: PinMatchMode? = url != nil ? .tab : nil
        pinTo(bundleID: bundleID, url: url, mode: mode, groupID: nil,
              appName: app.localizedName ?? bundleID)
    }

    /// Shared pin path used by both left-click and right-click menu options.
    private func pinTo(bundleID: String, url: String?, mode: PinMatchMode?,
                       groupID: UUID?, appName: String) {
        // Build a fully-updated Note struct, then do ONE assignment so SwiftUI's
        // @State setter definitely runs. Setting fields one at a time has
        // proven unreliable in some build configs.
        var updated = note
        updated.pinnedToApp = bundleID
        updated.pinnedToURL = url
        updated.pinMatchMode = mode
        updated.pinnedGroupID = groupID
        note = updated
        store.update(updated)
        onPin(bundleID, url, mode, groupID)

        let isChrome = ChromeBridge.isChrome(bundleID)
        if isChrome {
            switch mode {
            case .tab:
                showPinFeedback("Pinned to this Chrome tab")
            case .host:
                showPinFeedback("Pinned to this site")  // legacy mode
            case .group:
                let groupName = groupID.flatMap { groupStore.group(id: $0)?.name } ?? "group"
                showPinFeedback("Pinned to group: \(groupName)")
            case .none:
                showPinFeedback(url == nil
                    ? "Pinned to \(appName) (any tab)"
                    : "Pinned to \(appName) tab")
            }
        } else {
            showPinFeedback("Pinned to \(appName)")
        }
    }

    private func unpinNote() {
        let appHint = note.pinnedToApp?.split(separator: ".").last.map(String.init) ?? "app"
        var updated = note
        updated.pinnedToApp = nil
        updated.pinnedToURL = nil
        updated.pinMatchMode = nil
        updated.pinnedGroupID = nil
        note = updated
        store.update(updated)
        onUnpin()
        showPinFeedback("Unpinned from \(appHint)")
    }

    /// Try multiple sources for "which app was the user just on?"
    /// Falls through from the tracker to the system's frontmost.
    private func bestPinCandidate() -> NSRunningApplication? {
        if let app = FrontmostAppTracker.shared.lastNonSelf {
            return app
        }
        if let current = NSWorkspace.shared.frontmostApplication,
           current.bundleIdentifier != Bundle.main.bundleIdentifier {
            return current
        }
        return nil
    }

    private func showPinFeedback(_ msg: String) {
        withAnimation(.easeInOut(duration: 0.2)) { pinFeedback = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) { pinFeedback = nil }
        }
    }

    // MARK: - Options menu

    @ViewBuilder
    private var menuContents: some View {
        Menu("Color") {
            ForEach(NoteColor.allCases, id: \.self) { color in
                Button {
                    note.color = color
                    store.update(note)
                } label: {
                    if color == note.color {
                        Label(color.displayName, systemImage: "checkmark")
                    } else {
                        Text(color.displayName)
                    }
                }
            }
        }
        if !note.strokes.isEmpty {
            Button("Clear Drawing") {
                note.strokes.removeAll()
                store.update(note)
            }
        }
        Divider()
        Button("New Note",        action: onNewNote)
        Button("Show All Notes",  action: onShowHistory)
        Button("Settings…",        action: onShowSettings)
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete Note", systemImage: "trash")
        }
    }

    // MARK: - Persistence

    private func persistContent() {
        let range = NSRange(location: 0, length: attributedText.length)
        note.contentRTFD = try? attributedText.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
        note.content = attributedText.string
        store.update(note)
    }

    private func flushSave() {
        persistContent()
        withAnimation(.easeInOut(duration: 0.2)) { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) { showSavedToast = false }
        }
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8)  & 0xFF) / 255.0,
            blue:  Double(rgb         & 0xFF) / 255.0
        )
    }
}
