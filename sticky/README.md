# StickyNotes

A Mac Stickies–style app with global hotkeys, history search, custom keybinds, launch-at-login, and a clean modern UI. ~1000 lines of Swift, zero external dependencies.

## Features

- **⌃N** — create a new sticky note anywhere on screen (default — change in Settings)
- **⌃⇧N** — toggle the Raycast-style search/history panel
- **⌘,** from the menu bar — open Settings to rebind any hotkey
- Notes float on top of every app and every Space
- 6 colors per note, light + dark mode aware
- Minimal Stickies-style UI — controls fade in on hover, right-click for color/delete
- Window positions remembered per note
- Menu-bar-only (no Dock icon)
- **Launch at login** toggle in Settings
- Persists to `~/Library/Application Support/StickyNotes/notes.json`

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (only needed once, to build)

---

## Setup — Part 1: build the app (one-time, ~5 min)

1. **Create a new Xcode project**
   - File → New → Project → **macOS** → **App** → Next
   - Product Name: `StickyNotes`
   - Interface: **SwiftUI**, Language: **Swift**

2. **Drop in the source files**
   - Delete the auto-generated `ContentView.swift` and `StickyNotesApp.swift` (move to trash)
   - Drag everything in `Sources/` from this folder into the Xcode project navigator
   - When prompted: ✅ Copy items if needed, ✅ Add to target StickyNotes

3. **Make it a menu-bar-only app**
   - Click the project (top of navigator) → **StickyNotes** target → **Info** tab
   - Under "Custom macOS Application Target Properties", click **+**
   - Key: `Application is agent (UIElement)` (this is `LSUIElement`)
   - Value: `YES`

4. **Run it once to verify** (⌘R in Xcode)
   - Look for the note icon in your menu bar
   - Press **⌃N** — a sticky note should appear

---

## Setup — Part 2: install it permanently (no Xcode needed after this)

This makes the app live in `/Applications` and start automatically at login. Xcode can be closed forever.

1. **Build a release version**
   - In Xcode: **Product → Archive**
   - When the Organizer window opens, click **Distribute App** → **Custom** → **Copy App** → Next → choose a location (Desktop is fine)
   - You'll get a `StickyNotes.app` file

   *Alternative quick path:* **Product → Build** (⌘B), then **Product → Show Build Folder in Finder** → `Products/Debug/StickyNotes.app`. Less polished but identical for personal use.

2. **Install it**
   - Drag `StickyNotes.app` into `/Applications`
   - Double-click it to launch. macOS may say "unidentified developer" the first time — right-click → **Open**, then click **Open** in the dialog

3. **Enable launch at login**
   - Click the menu-bar icon → **Settings…**
   - Toggle **Launch at login** on
   - That's it. The app will start every time you log in to your Mac

4. **(Optional) Quit Xcode forever** — you don't need it anymore unless you want to change the code

---

## Customizing hotkeys

Click the menu-bar icon → **Settings…** → click any shortcut → press the new combo.

- Press **Escape** while recording to cancel
- Requires at least one modifier (⌃ ⌥ ⇧ ⌘) — a bare letter would fire on every keypress

### About the default ⌃N

⌃N is the macOS-wide Emacs binding for "move cursor down one line" in text fields and terminals. With ⌃N as a global hotkey, that binding is preempted everywhere. If that bothers you, change it in Settings — good alternatives:

- **⌃⌘N** — rarely used by other apps
- **⌥Space** — Raycast-style
- **F1 / F2 / etc.** — no conflicts at all

---

## Customizing the look

Pure SwiftUI, easy to edit:

| File | What's in it |
|---|---|
| `NoteView.swift` | Note appearance — corner radius, padding, hover buttons, fonts |
| `HistoryView.swift` | Search panel — size (`.frame(width:height:)`), the `.regularMaterial` blur |
| `Note.swift` | The 6 colors. Add a case to `NoteColor` with a (light, dark) hex pair and it shows up everywhere automatically |
| `SettingsView.swift` | Settings window layout |

---

## File map

```
Sources/
├── StickyNotesApp.swift   # @main entry point
├── AppDelegate.swift      # Window/menu management, hotkey wiring
├── HotkeyManager.swift    # Carbon global hotkey wrapper
├── Note.swift             # Note model + color enum
├── NoteStore.swift        # JSON persistence (debounced writes)
├── NoteWindow.swift       # NSWindow subclass for floating notes
├── NoteView.swift         # Sticky note UI (minimal, hover-revealed controls)
├── HistoryView.swift      # Raycast-style search panel
├── SettingsStore.swift    # Hotkey + launch-at-login persistence
├── SettingsView.swift     # Settings window
└── HotkeyRecorder.swift   # Key-combo capture component
```

---

## Troubleshooting

**Hotkey doesn't work / nothing happens on ⌃N.**
Another app may already own that hotkey globally. Open Settings → rebind to something less common (⌃⌘N, ⌥Space, or an F-key).

**"Launch at login" doesn't stick.**
This uses Apple's modern `SMAppService` API, which requires the app to live in `/Applications` (not Desktop, not Downloads). Move it there and toggle again.

**Built once but want to change something later.**
Reopen the Xcode project, edit, **Product → Archive → Distribute → Copy App** again, replace the app in `/Applications`. Your notes are stored separately in Application Support and won't be affected.

**Want the new-note hotkey to also focus an existing empty note instead of always creating one.**
In `AppDelegate.swift`'s `newNote()`, check `NoteStore.shared.notes.first` — if its content is empty, show that instead of creating a new one.
