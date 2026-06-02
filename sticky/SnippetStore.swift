//
//  Snippet.swift
//  sticky
//
//  Created by Max Zhang on 6/1/26.
//


import Foundation
import Combine

/// A text-expansion snippet. Type the trigger, press Tab, and it expands.
/// Use `$0` in the expansion to mark where the cursor should land after
/// expansion (e.g. `\frac{$0}{}` puts the cursor between the first braces).
struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var trigger: String
    var expansion: String

    init(id: UUID = UUID(), trigger: String = "", expansion: String = "") {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published var snippets: [Snippet] = [] {
        didSet { save() }
    }

    private let key = "stickyNotes.snippets"

    private init() {
        load()
    }

    func add() {
        snippets.append(Snippet(trigger: "", expansion: ""))
    }

    func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
    }

    /// Look at the characters immediately before the cursor and try to find a
    /// matching snippet trigger. A trigger matches if it's the trailing token
    /// after the last whitespace/start-of-document, exactly.
    ///
    /// Returns the trigger length (how many chars to delete behind the cursor),
    /// the expansion text (with `$0` removed), and the cursor offset within
    /// the expansion where the cursor should land.
    func match(textBeforeCursor prefix: String) -> (triggerLength: Int, expansion: String, cursorOffset: Int)? {
        // Scan back to last whitespace boundary to find the candidate trigger.
        var i = prefix.endIndex
        while i > prefix.startIndex {
            let prev = prefix.index(before: i)
            if prefix[prev].isWhitespace { break }
            i = prev
        }
        let candidate = String(prefix[i..<prefix.endIndex])
        guard !candidate.isEmpty else { return nil }
        guard let snippet = snippets.first(where: { $0.trigger == candidate }) else {
            return nil
        }

        // Find $0 (cursor marker); strip it from the output.
        var expansion = snippet.expansion
        var cursorOffset = expansion.count
        if let r = expansion.range(of: "$0") {
            cursorOffset = expansion.distance(from: expansion.startIndex, to: r.lowerBound)
            expansion.removeSubrange(r)
        }

        return (candidate.count, expansion, cursorOffset)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else {
            return
        }
        snippets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}