import SwiftUI
import AppKit

/// SwiftUI wrapper around NSTextView. Supports:
///   • ⌘B bold, ⌘I italic, ⌘U underline (Google Docs–style)
///   • ⌘⇧H highlight (toggles selection background to `highlightColor`)
///   • Rich paste: text, images, GIFs (via importsGraphics = true)
///   • Standard right-click menu
///
/// The bold/italic/underline shortcuts are wired manually inside RichNoteTextView
/// because we're an LSUIElement app (no menu bar) — without a Format menu the
/// system's default ⌘B/I/U bindings don't fire.
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

// MARK: - The text view with all the keybindings

final class RichNoteTextView: NSTextView {
    var highlightColor: NSColor = NSColor(red: 1, green: 0.92, blue: 0.3, alpha: 0.55)

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key  = (event.charactersIgnoringModifiers ?? "").lowercased()

        // ⌘B / ⌘I / ⌘U — Google Docs bindings
        if mods == [.command] {
            switch key {
            case "b": toggleTrait(.boldFontMask);   return
            case "i": toggleTrait(.italicFontMask); return
            case "u": toggleUnderline();             return
            default: break
            }
        }

        // ⌘⇧H — highlight
        if mods == [.command, .shift], key == "h" {
            toggleHighlight()
            return
        }

        super.keyDown(with: event)
    }

    // MARK: Bold / Italic (font traits)

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        let fontManager = NSFontManager.shared

        // No selection — toggle typingAttributes so subsequent text gets the trait.
        if range.length == 0 {
            var attrs = typingAttributes
            let current = (attrs[.font] as? NSFont) ?? font ?? NSFont.systemFont(ofSize: 14)
            let hasTrait = fontManager.traits(of: current).contains(trait)
            attrs[.font] = hasTrait
                ? fontManager.convert(current, toNotHaveTrait: trait)
                : fontManager.convert(current, toHaveTrait: trait)
            typingAttributes = attrs
            return
        }

        // Selection — apply to selected runs.
        guard let storage = textStorage else { return }
        var allHave = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            guard let font = value as? NSFont else { allHave = false; return }
            if !fontManager.traits(of: font).contains(trait) {
                allHave = false
                stop.pointee = true
            }
        }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let updated = allHave
                ? fontManager.convert(current, toNotHaveTrait: trait)
                : fontManager.convert(current, toHaveTrait: trait)
            storage.addAttribute(.font, value: updated, range: subrange)
        }
        storage.endEditing()
        notifyChange()
    }

    // MARK: Underline (attribute, not a font trait)

    private func toggleUnderline() {
        let range = selectedRange()

        // No selection — toggle typing attribute.
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

        // No selection — toggle typing attribute.
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

    private func notifyChange() {
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }
}
