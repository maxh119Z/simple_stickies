import SwiftUI
import AppKit

struct GroupsView: View {
    @ObservedObject private var store = TabGroupStore.shared
    @State private var newGroupName: String = ""
    @State private var renameTarget: UUID?
    @State private var renameDraft: String = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("New group name", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { createGroup() }
                    Button("Create") { createGroup() }
                        .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("New Group").font(.headline)
            } footer: {
                Text("Use ⌃⌘N while on a Chrome tab to add it to the active group (shown with ★). Or right-click a sticky note's pin button → Add tab to group.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if store.groups.isEmpty {
                Section {
                    Text("No tab groups yet — create one above.")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(store.groups) { group in
                    groupSection(group)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
    }

    @ViewBuilder
    private func groupSection(_ group: TabGroup) -> some View {
        let isActive = store.activeGroupID == group.id

        Section {
            HStack(spacing: 8) {
                if renameTarget == group.id {
                    TextField("Group name", text: $renameDraft, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                } else {
                    if isActive {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .help("Active group — ⌃⌘N adds the current Chrome tab here")
                    }
                    Text(group.name).font(.headline)
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
                Button {
                    beginRename(group)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Rename")

                Button(role: .destructive) {
                    confirmDelete(group)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete group")
            }

            if group.urls.isEmpty {
                Text("No tabs in this group yet.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(group.urls, id: \.self) { url in
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(TabGroup.displayName(for: url))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(url)
                        Spacer()
                        Button {
                            store.removeTab(url, from: group.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from group")
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.create(name: name)
        newGroupName = ""
    }

    private func beginRename(_ group: TabGroup) {
        renameTarget = group.id
        renameDraft = group.name
    }

    private func commitRename() {
        defer { renameTarget = nil }
        guard let id = renameTarget else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.rename(id: id, to: name)
    }

    private func confirmDelete(_ group: TabGroup) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(group.name)\"?"
        alert.informativeText = "Notes pinned to this group will stop showing automatically. This doesn't affect your actual Chrome tabs."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.delete(id: group.id)
        }
    }
}
