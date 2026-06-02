import SwiftUI
import AppKit
import Carbon.HIToolbox  // for kVK_Tab

/// SwiftUI wrapper around NSTextView. Supports:
///   • ⌘B bold, ⌘I italic, ⌘U underline (Google Docs–style)
///   • ⌘⇧H highlight (toggles selection background to `highlightColor`)
///   • ⌘= / ⌘+ / ⌘- — grow/shrink selected (or typing) font size
///   • Right-click → Clear Formatting / Increase Text Size / Decrease Text Size
///   • Tab → expand a custom text snippet if the trigger matches
///   • Live LaTeX rendering: `$$...$$` blocks become inline images when the
///     cursor isn't inside them; click a rendered block to expand back to
///     source for editing.
///   • Click a pasted image → 4-handle resize overlay (Google Docs–style)
///   • Rich paste (images, GIFs) via importsGraphics = true
///
/// Bold/italic/underline shortcuts are wired manually inside RichNoteTextView
/// because we're an LSUIElement app (no Format menu, so the system bindings
/// don't fire by themselves).
struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var highlightColor: NSColor
    var defaultTextColor: NSColor = .black
    var onTextChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = RichNoteTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = defaultTextColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.highlightColor = highlightColor

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? RichNoteTextView else { return }
        textView.highlightColor = highlightColor
        if !textView.attributedString().isEqual(to: attributedText) {
            let sel = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            let safeLoc = min(sel.location, textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.attributedText = tv.attributedString()
            parent.onTextChange()
        }
    }
}

// MARK: - The text view with all the keybindings and right-click extras

final class RichNoteTextView: NSTextView {
    var highlightColor: NSColor = NSColor(red: 1, green: 0.92, blue: 0.3, alpha: 0.55)

    // Image-resize overlay (Google Docs–style handles on selected attachments)
    private var imageResizeOverlay: ImageResizeOverlay?

    // Math-rendering state. We debounce passes to coalesce rapid keystrokes;
    // `inMathPass` prevents the pass's own storage mutations from re-entering
    // through didChangeText.
    private var mathPassWork: DispatchWorkItem?
    private var inMathPass = false

    // MARK: - Right-click menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        let clearItem = NSMenuItem(
            title: "Clear Formatting",
            action: #selector(clearFormattingAction),
            keyEquivalent: ""
        )
        let increaseItem = NSMenuItem(
            title: "Increase Text Size",
            action: #selector(increaseFontSizeAction),
            keyEquivalent: "+"
        )
        increaseItem.keyEquivalentModifierMask = [.command]

        let decreaseItem = NSMenuItem(
            title: "Decrease Text Size",
            action: #selector(decreaseFontSizeAction),
            keyEquivalent: "-"
        )
        decreaseItem.keyEquivalentModifierMask = [.command]

        for item in [clearItem, increaseItem, decreaseItem] {
            item.target = self
        }

        menu.insertItem(.separator(), at: 0)
        menu.insertItem(decreaseItem, at: 0)
        menu.insertItem(increaseItem, at: 0)
        menu.insertItem(clearItem, at: 0)

        return menu
    }

    @objc func clearFormattingAction() { clearFormatting() }
    @objc func increaseFontSizeAction() { changeFontSize(by: 2) }
    @objc func decreaseFontSizeAction() { changeFontSize(by: -2) }

    // MARK: - Keybindings

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key  = (event.charactersIgnoringModifiers ?? "").lowercased()

        // Tab (no modifiers) → try snippet expansion first; fall through if no match.
        if mods.isEmpty && Int(event.keyCode) == kVK_Tab {
            if tryExpandSnippet() { return }
        }

        if mods == [.command] {
            switch key {
            case "b": toggleTrait(.boldFontMask);   return
            case "i": toggleTrait(.italicFontMask); return
            case "u": toggleUnderline();            return
            case "=", "+": changeFontSize(by: 2);   return
            case "-": changeFontSize(by: -2);       return
            default: break
            }
        }

        if mods == [.command, .shift] {
            if key == "h" {
                toggleHighlight()
                return
            }
            if key == "+" || key == "=" { changeFontSize(by: 2);  return }
            if key == "_" || key == "-" { changeFontSize(by: -2); return }
        }

        super.keyDown(with: event)
    }

    // MARK: - Snippet expansion

    private func tryExpandSnippet() -> Bool {
        guard let storage = textStorage else { return false }
        let cursor = selectedRange().location
        guard cursor > 0 else { return false }

        let ns = storage.string as NSString
        // Look at up to 64 chars before the cursor — plenty for any reasonable
        // trigger word. The snippet store scans back to the last whitespace.
        let lookback = min(64, cursor)
        let prefix = ns.substring(with: NSRange(location: cursor - lookback,
                                                length: lookback))

        guard let match = SnippetStore.shared.match(textBeforeCursor: prefix) else {
            return false
        }

        let triggerRange = NSRange(location: cursor - match.triggerLength,
                                   length: match.triggerLength)

        // Use the current typing attributes so the expansion picks up the
        // surrounding font/size/color rather than a hardcoded default.
        let attrs = typingAttributes
        let replacement = NSAttributedString(string: match.expansion, attributes: attrs)

        storage.beginEditing()
        storage.replaceCharacters(in: triggerRange, with: replacement)
        storage.endEditing()

        // Land the cursor at the $0 position (or end of expansion if no marker).
        let newCursor = triggerRange.location + match.cursorOffset
        setSelectedRange(NSRange(location: newCursor, length: 0))

        notifyChange()
        return true
    }

    // MARK: - Clear formatting

    private func clearFormatting() {
        let target = effectiveTargetRange()
        guard target.length > 0, let storage = textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: target, options: []) { attrs, subrange, _ in
            var keep: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.black
            ]
            if let attachment = attrs[.attachment] {
                keep[.attachment] = attachment
            }
            storage.setAttributes(keep, range: subrange)
        }
        storage.endEditing()
        notifyChange()
    }

    // MARK: - Font size

    private func changeFontSize(by delta: CGFloat) {
        let range = selectedRange()
        let fm = NSFontManager.shared

        if range.length == 0 {
            var attrs = typingAttributes
            let current = (attrs[.font] as? NSFont) ?? font ?? NSFont.systemFont(ofSize: 14)
            let newSize = max(8, min(72, current.pointSize + delta))
            attrs[.font] = fm.convert(current, toSize: newSize)
            typingAttributes = attrs
            return
        }

        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let newSize = max(8, min(72, current.pointSize + delta))
            storage.addAttribute(.font, value: fm.convert(current, toSize: newSize), range: subrange)
        }
        storage.endEditing()
        notifyChange()
    }

    private func effectiveTargetRange() -> NSRange {
        let sel = selectedRange()
        if sel.length > 0 { return sel }
        return NSRange(location: 0, length: textStorage?.length ?? 0)
    }

    // MARK: - Image resize overlay

    override func setSelectedRanges(_ ranges: [NSValue],
                                    affinity: NSSelectionAffinity,
                                    stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !stillSelectingFlag {
            updateImageResizeOverlay()
            scheduleMathPass()  // cursor move may enter/leave a math block
        }
    }

    override func didChangeText() {
        super.didChangeText()
        if !inMathPass {
            updateImageResizeOverlay()
            scheduleMathPass()
        }
    }

    private func updateImageResizeOverlay() {
        let range = selectedRange()
        guard range.length == 1, let storage = textStorage else {
            hideImageResizeOverlay()
            return
        }
        let attrs = storage.attributes(at: range.location, effectiveRange: nil)
        guard let attachment = attrs[.attachment] as? NSTextAttachment,
              // Math attachments don't get a resize overlay — they re-render
              // automatically from source.
              !(attachment is MathAttachment),
              let image = attachmentImage(from: attachment) else {
            hideImageResizeOverlay()
            return
        }
        showImageResizeOverlay(attachment: attachment, range: range, image: image)
    }

    private func attachmentImage(from attachment: NSTextAttachment) -> NSImage? {
        if let img = attachment.image { return img }
        if let cell = attachment.attachmentCell as? NSTextAttachmentCell, let img = cell.image {
            return img
        }
        if let data = attachment.fileWrapper?.regularFileContents,
           let img = NSImage(data: data) {
            return img
        }
        return nil
    }

    private func showImageResizeOverlay(attachment: NSTextAttachment,
                                        range: NSRange, image: NSImage) {
        guard let lm = layoutManager, let tc = textContainer else { return }
        let glyphRange = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let offset = textContainerOrigin
        let frameInView = NSRect(x: rect.origin.x + offset.x,
                                 y: rect.origin.y + offset.y,
                                 width: rect.width, height: rect.height)

        if imageResizeOverlay == nil {
            let overlay = ImageResizeOverlay()
            overlay.parentTextView = self
            addSubview(overlay)
            imageResizeOverlay = overlay
        }

        imageResizeOverlay?.configure(attachment: attachment, range: range,
                                      originalImageSize: image.size)
        imageResizeOverlay?.frame = frameInView
        imageResizeOverlay?.isHidden = false
        imageResizeOverlay?.needsDisplay = true
    }

    private func hideImageResizeOverlay() {
        imageResizeOverlay?.isHidden = true
    }

    func repositionImageResizeOverlay() {
        guard let overlay = imageResizeOverlay, !overlay.isHidden else { return }
        guard let lm = layoutManager, let tc = textContainer else { return }
        let glyphRange = lm.glyphRange(forCharacterRange: overlay.currentRange,
                                       actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let offset = textContainerOrigin
        overlay.frame = NSRect(x: rect.origin.x + offset.x,
                               y: rect.origin.y + offset.y,
                               width: rect.width, height: rect.height)
    }

    // MARK: - Math rendering pass
    //
    // Two phases run on every (debounced) text or selection change:
    //   1. EXPAND: any MathAttachment that the cursor is now adjacent to or
    //      inside is replaced with its raw "$$source$$" text — so the user
    //      can edit it.
    //   2. RENDER: any complete `$$...$$` run that the cursor is NOT inside
    //      is replaced with a freshly-rendered MathAttachment.
    //
    // The pass disables undo registration around its mutations so the user's
    // Cmd-Z undoes their typing, not our auto-render.

    private func scheduleMathPass() {
        guard !inMathPass else { return }
        mathPassWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runMathPass() }
        mathPassWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func runMathPass() {
        guard !inMathPass else { return }
        guard let storage = textStorage else { return }

        inMathPass = true
        defer { inMathPass = false }

        let undo = undoManager
        undo?.disableUndoRegistration()
        defer { undo?.enableUndoRegistration() }

        var didChange = false
        let originalCursor = selectedRange().location
        var cursor = originalCursor

        // ---------- Phase 1: expand attachments adjacent to/under the cursor ----------
        var expansions: [(NSRange, String)] = []
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, range, _ in
            guard let math = value as? MathAttachment else { return }
            // Attachment is 1 char at range.location. Cursor positions that
            // count as "on" it are range.location and range.location + 1.
            let left = range.location
            let right = range.location + range.length
            if cursor >= left && cursor <= right {
                expansions.append((range, "$$\(math.latexSource)$$"))
            }
        }

        if !expansions.isEmpty {
            storage.beginEditing()
            for (range, source) in expansions.reversed() {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.black
                ]
                let delta = source.utf16.count - range.length
                storage.replaceCharacters(in: range,
                                          with: NSAttributedString(string: source, attributes: attrs))
                // Shift cursor if it was at/after this range
                if cursor >= range.location + range.length {
                    cursor += delta
                } else if cursor >= range.location {
                    // Cursor was on the attachment — land it just after the closing $$
                    cursor = range.location + source.utf16.count
                }
            }
            storage.endEditing()
            didChange = true
            setSelectedRange(NSRange(location: cursor, length: 0))
        }

        // ---------- Phase 2: render $$...$$ blocks not under the cursor ----------
        let text = storage.string as NSString
        guard let regex = try? NSRegularExpression(pattern: "\\$\\$([^$]+?)\\$\\$", options: []) else {
            if didChange { notifyChange() }
            return
        }
        let fullRange = NSRange(location: 0, length: text.length)
        let matches = regex.matches(in: text as String, options: [], range: fullRange)

        // Process in reverse so earlier ranges aren't shifted by later replacements.
        for match in matches.reversed() {
            let outer = match.range
            let inner = match.range(at: 1)

            // Skip if cursor is inside or at either boundary of this block.
            let left = outer.location
            let right = outer.location + outer.length
            if cursor >= left && cursor <= right { continue }

            let source = text.substring(with: inner)
            guard let image = MathRenderer.render(latex: source) else { continue }

            let attachment = MathAttachment(source: source, image: image)
            let attrString = NSAttributedString(attachment: attachment)

            storage.beginEditing()
            let delta = attrString.length - outer.length
            storage.replaceCharacters(in: outer, with: attrString)
            storage.endEditing()
            didChange = true

            // Shift cursor if it was after this block.
            if cursor >= outer.location + outer.length {
                cursor += delta
            }
        }

        if didChange {
            setSelectedRange(NSRange(location: min(cursor, storage.length), length: 0))
            notifyChange()
        }
    }

    // MARK: Bold / Italic (font traits)

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        let fm = NSFontManager.shared

        if range.length == 0 {
            var attrs = typingAttributes
            let current = (attrs[.font] as? NSFont) ?? font ?? NSFont.systemFont(ofSize: 14)
            let hasTrait = fm.traits(of: current).contains(trait)
            attrs[.font] = hasTrait
                ? fm.convert(current, toNotHaveTrait: trait)
                : fm.convert(current, toHaveTrait: trait)
            typingAttributes = attrs
            return
        }

        guard let storage = textStorage else { return }
        var allHave = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            guard let font = value as? NSFont else { allHave = false; return }
            if !fm.traits(of: font).contains(trait) {
                allHave = false
                stop.pointee = true
            }
        }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let updated = allHave
                ? fm.convert(current, toNotHaveTrait: trait)
                : fm.convert(current, toHaveTrait: trait)
            storage.addAttribute(.font, value: updated, range: subrange)
        }
        storage.endEditing()
        notifyChange()
    }

    // MARK: Underline

    private func toggleUnderline() {
        let range = selectedRange()

        if range.length == 0 {
            var attrs = typingAttributes
            let current = (attrs[.underlineStyle] as? Int) ?? 0
            attrs[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            typingAttributes = attrs
            return
        }

        guard let storage = textStorage else { return }
        var allUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
            let style = (value as? Int) ?? 0
            if style == 0 { allUnderlined = false }
        }

        storage.beginEditing()
        if allUnderlined {
            storage.removeAttribute(.underlineStyle, range: range)
        } else {
            storage.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.single.rawValue,
                                 range: range)
        }
        storage.endEditing()
        notifyChange()
    }

    // MARK: Highlight (background color)

    private func toggleHighlight() {
        let range = selectedRange()

        if range.length == 0 {
            var attrs = typingAttributes
            if (attrs[.backgroundColor] as? NSColor) == highlightColor {
                attrs[.backgroundColor] = nil
            } else {
                attrs[.backgroundColor] = highlightColor
            }
            typingAttributes = attrs
            return
        }

        guard let storage = textStorage else { return }
        var allHighlighted = true
        storage.enumerateAttribute(.backgroundColor, in: range, options: []) { value, _, _ in
            if (value as? NSColor) != highlightColor { allHighlighted = false }
        }

        storage.beginEditing()
        if allHighlighted {
            storage.removeAttribute(.backgroundColor, range: range)
        } else {
            storage.addAttribute(.backgroundColor, value: highlightColor, range: range)
        }
        storage.endEditing()
        notifyChange()
    }

    func notifyChange() {
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }
}

// MARK: - Image resize overlay

final class ImageResizeOverlay: NSView {
    weak var parentTextView: RichNoteTextView?
    private(set) var currentAttachment: NSTextAttachment?
    private(set) var currentRange: NSRange = NSRange(location: 0, length: 0)
    private var originalImageSize: NSSize = NSSize(width: 100, height: 100)

    private let handleRadius: CGFloat = 5
    private let hitSlop: CGFloat = 4

    private enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private var activeHandle: HandlePosition?
    private var dragStartLocation: NSPoint = .zero
    private var dragStartSize: NSSize = .zero

    override var isFlipped: Bool { true }

    func configure(attachment: NSTextAttachment, range: NSRange, originalImageSize: NSSize) {
        self.currentAttachment = attachment
        self.currentRange = range
        self.originalImageSize = originalImageSize
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.75, dy: 0.75))
        border.lineWidth = 1.5
        border.stroke()

        for pos in HandlePosition.allCases {
            let c = handleCenter(for: pos)
            let r = NSRect(x: c.x - handleRadius, y: c.y - handleRadius,
                           width: handleRadius * 2, height: handleRadius * 2)
            let path = NSBezierPath(ovalIn: r)
            NSColor.white.setFill()
            path.fill()
            NSColor.systemBlue.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func handleCenter(for pos: HandlePosition) -> NSPoint {
        switch pos {
        case .topLeft:     return NSPoint(x: 0, y: 0)
        case .topRight:    return NSPoint(x: bounds.width, y: 0)
        case .bottomLeft:  return NSPoint(x: 0, y: bounds.height)
        case .bottomRight: return NSPoint(x: bounds.width, y: bounds.height)
        }
    }

    private func handle(at point: NSPoint) -> HandlePosition? {
        for pos in HandlePosition.allCases {
            let c = handleCenter(for: pos)
            let dx = point.x - c.x
            let dy = point.y - c.y
            let r = handleRadius + hitSlop
            if dx*dx + dy*dy <= r * r { return pos }
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return handle(at: local) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let h = handle(at: p), let attachment = currentAttachment else { return }
        activeHandle = h
        dragStartLocation = p
        dragStartSize = attachment.bounds.size
    }

    override func mouseDragged(with event: NSEvent) {
        guard let h = activeHandle,
              let attachment = currentAttachment,
              let tv = parentTextView else { return }

        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - dragStartLocation.x
        let dy = p.y - dragStartLocation.y

        var w = dragStartSize.width
        var height = dragStartSize.height
        switch h {
        case .topLeft:     w -= dx; height -= dy
        case .topRight:    w += dx; height -= dy
        case .bottomLeft:  w -= dx; height += dy
        case .bottomRight: w += dx; height += dy
        }

        let aspect = originalImageSize.width / max(originalImageSize.height, 1)
        if !event.modifierFlags.contains(.shift) {
            if abs(dx) >= abs(dy) {
                height = w / aspect
            } else {
                w = height * aspect
            }
        }

        w = max(40, min(2000, w))
        height = max(40, min(2000, height))

        attachment.bounds = NSRect(origin: .zero, size: NSSize(width: w, height: height))

        tv.textStorage?.edited(.editedAttributes, range: currentRange, changeInLength: 0)
        tv.layoutManager?.invalidateLayout(forCharacterRange: currentRange,
                                           actualCharacterRange: nil)
        tv.needsDisplay = true
        tv.repositionImageResizeOverlay()
    }

    override func mouseUp(with event: NSEvent) {
        activeHandle = nil
        parentTextView?.notifyChange()
    }
}
