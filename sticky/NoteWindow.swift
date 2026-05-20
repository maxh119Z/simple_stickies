import AppKit
import SwiftUI

/// Subclass of NSHostingView that responds to clicks even when the window isn't
/// the active window. This fixes the "click X while Chrome focused" bug —
/// without this, the first click only activates our app, the click is lost.
final class FirstResponderHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, transparent, always-on-top window for a sticky note.
final class NoteWindow: NSWindow {
    let noteID: UUID

    init(noteID: UUID, rootView: some View, initialFrame: NSRect?) {
        self.noteID = noteID
        let defaultSize = NSSize(width: 320, height: 280)
        let frame = initialFrame ?? NSRect(origin: .zero, size: defaultSize)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 220, height: 160)

        let hosting = FirstResponderHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.contentView = hosting

        if initialFrame == nil { center() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
