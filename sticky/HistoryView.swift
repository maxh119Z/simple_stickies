import SwiftUI

struct HistoryView: View {
    @ObservedObject var store = NoteStore.shared
    @State private var query = ""
    @State private var selectedID: UUID?

    var onSelect: (Note) -> Void
    var onClose: () -> Void

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.notes }
        return store.notes.filter { $0.content.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 540, height: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            // Hidden button so Escape closes the panel.
            Button("Close", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .onAppear {
            selectedID = filtered.first?.id
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondary)

            TextField("Search notes…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .onSubmit {
                    if let id = selectedID, let note = store.note(for: id) {
                        onSelect(note)
                    }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            // Real close button (was missing — the search-clear X above only clears the query)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { note in
                            HistoryRow(
                                note: note,
                                isSelected: selectedID == note.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(note) }
                            .onHover { hovering in
                                if hovering { selectedID = note.id }
                            }
                            .contextMenu {
                                Button("Open") { onSelect(note) }
                                Button("Delete", role: .destructive) {
                                    store.delete(note)
                                }
                            }
                            .id(note.id)
                        }
                    }
                }
            }
            .onChange(of: selectedID) { _, newID in
                if let id = newID {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(query.isEmpty ? "No notes yet" : "No matches")
                .font(.headline)
                .foregroundColor(.secondary)
            if query.isEmpty {
                Text("Press ⌘N to create your first note")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                let n = Note()
                store.add(n)
                onSelect(n)
            } label: {
                Label("New Note", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            Text("\(filtered.count) \(filtered.count == 1 ? "note" : "notes")")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let note: Note
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: colorScheme == .dark ? note.color.hex.dark : note.color.hex.light))
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.firstLine.isEmpty ? "Empty note" : note.firstLine)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(note.firstLine.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Text(note.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(isSelected ? 1 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.18)
                : Color.clear
        )
    }
}
