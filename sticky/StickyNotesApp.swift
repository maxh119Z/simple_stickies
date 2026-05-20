import SwiftUI

@main
struct StickyNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We manage windows manually via AppDelegate so the Scene is empty.
        // This keeps SwiftUI from auto-opening a main window on launch.
        Settings { EmptyView() }
    }
}
