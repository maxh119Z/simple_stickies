import SwiftUI
import AppKit

struct GroupsView: View {
    @ObservedObject private var store = TabGroupStore.shared
    @State private var newGroupName: String = ""
    @State private var editingGroup: UUID? = nil
    @State private var renameDraft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            createBar
            Divider()
            groupsList
        }
        .frame(minWidth: 500, minHeight: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.stack")
            Text("Tab Groups").font(.title3.weight(.semibold))
            Spacer()
            Text("\(store.groups.count) group\(store.groups.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - New group bar

    private var createBar: some View {
        HStack(spacing: 8) {
            TextField("New group name", text: $newGroupName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { createGroup() }
            Button("Create") { createGroup() }
                .keyboardShortcut(.defaultAction)
                .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List of groups

    private var groupsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.groups.isEmpty {
                    emptyState
                } else {
                    ForEach(store.groups) { group in
                        groupRow(group)
                        Divider()
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.title)
                .foregroundColor(.secondary)
            Text("No tab groups yet")
                .font(.headline)
            Text("Create one above, then use ⌃⌘N while on a Chrome tab to add it to the active group (shown with ★).")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func groupRow(_ group: TabGroup) -> some View {
        let isActive = store.activeGroupID == group.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isActive {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .help("Active group — ⌃⌘N adds the current Chrome tab here")
                }
                if editingGroup == group.id {
                    TextField("Name", text: $renameDraft, onCommit: {
                        commitRename(group)
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                } else {
                    Text(group.name).font(.headline)
                        .onTapGesture(count: 2) { startEditing(group) }
                }
                Text("\(group.urls.count) tab\(group.urls.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                if !isActive {
                    Button("Set Active") { store.setActive(group.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button { startEditing(group) } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Rename")

                Button(role: .destructive) { confirmDelete(group) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete group")
            }

            if group.urls.isEmpty {
                Text("No tabs in this group yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                    .padding(.bottom, 2)
            } else {
                ForEach(group.urls, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(TabGroup.displayName(for: url))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(url)
                        Spacer()
                        Button { store.removeTab(url, from: group.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove tab from group")
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.create(name: name)
        newGroupName = ""
    }

    private func startEditing(_ group: TabGroup) {
        editingGroup = group.id
        renameDraft = group.name
    }

    private func commitRename(_ group: TabGroup) {
        defer { editingGroup = nil }
        let name = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.rename(id: group.id, to: name)
    }

    private func confirmDelete(_ group: TabGroup) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(group.name)\"?"
        alert.informativeText = "Notes pinned to this group will stop showing automatically. Your actual Chrome tabs are unaffected."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.delete(id: group.id)
        }
    }
}
