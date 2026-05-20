import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A button that captures the next keyboard combo and writes it to the binding.
/// Press Escape while recording to cancel. Plain key (no modifier) is rejected
/// to avoid binding a hotkey that would fire on every keypress.
struct HotkeyRecorder: View {
    @Binding var hotkey: HotkeySetting
    @State private var recording = false
    @State private var monitor: Any?
    @State private var flagsMonitor: Any?
    @State private var liveFlags: NSEvent.ModifierFlags = []

    var body: some View {
        Button(action: toggle) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .frame(minWidth: 110, minHeight: 22)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            recording ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: recording ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private var label: String {
        if recording {
            let preview = previewString(liveFlags)
            return preview.isEmpty ? "Press keys…" : preview + "…"
        }
        return hotkey.displayString
    }

    private func previewString(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control)  { s += "⌃" }
        if flags.contains(.option)   { s += "⌥" }
        if flags.contains(.shift)    { s += "⇧" }
        if flags.contains(.command)  { s += "⌘" }
        return s
    }

    private func toggle() {
        if recording { stop() } else { start() }
    }

    private func start() {
        recording = true
        liveFlags = []

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            liveFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return event
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil  // swallow the event so it doesn't go to the focused text field
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        monitor = nil
        flagsMonitor = nil
        recording = false
        liveFlags = []
    }

    private func handle(_ event: NSEvent) {
        // Escape cancels recording without saving
        if Int(event.keyCode) == kVK_Escape {
            stop()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifierKeys: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let hasModifier = !flags.intersection(modifierKeys).isEmpty

        // Require at least one modifier so a bare letter doesn't become a global hotkey.
        guard hasModifier else { return }

        hotkey = HotkeySetting(
            keyCode: Int(event.keyCode),
            modifiers: carbonModifiers(from: flags)
        )
        stop()
    }
}
