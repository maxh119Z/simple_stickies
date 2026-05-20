import Foundation
import Combine

@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [Note] = []

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyNotes", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("notes.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // File doesn't exist yet → fresh install, normal case.
            return
        }
        guard !data.isEmpty else { return }

        do {
            let decoded = try JSONDecoder().decode([Note].self, from: data)
            notes = decoded.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            // Decode failed but the file has content — preserve it so the user
            // doesn't lose their data the next time we save. Rename to a backup
            // file with a timestamp; don't touch the original anymore until the
            // user-visible notes are written explicitly.
            let stamp = Int(Date().timeIntervalSince1970)
            let backupURL = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupted-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            NSLog("StickyNotes: notes.json failed to decode (\(error)). Backed up to \(backupURL.lastPathComponent).")
        }
    }

    /// Debounced write so typing in a note doesn't hammer the disk.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.writeNow()
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func writeNow() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations

    func add(_ note: Note) {
        notes.insert(note, at: 0)
        scheduleSave()
    }

    func update(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.updatedAt = Date()
        notes[idx] = updated
        // Resort so most-recent floats to the top of history.
        notes.sort { $0.updatedAt > $1.updatedAt }
        scheduleSave()
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        scheduleSave()
    }

    func note(for id: UUID) -> Note? {
        notes.first(where: { $0.id == id })
    }
}
