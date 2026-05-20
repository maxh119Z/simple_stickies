//
//  TabGroup.swift
//  sticky
//
//  Created by Max Zhang on 5/19/26.
//


import Foundation
import Combine

struct TabGroup: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var urls: [String]           // canonical URLs
    var createdAt: Date
    var updatedAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.urls = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Pretty display for a stored URL — drops scheme, returns "host/path".
    static func displayName(for url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        let path = u.path
        if path.isEmpty || path == "/" { return host }
        return host + path
    }
}

final class TabGroupStore: ObservableObject {
    static let shared = TabGroupStore()

    @Published private(set) var groups: [TabGroup] = []
    @Published private(set) var activeGroupID: UUID?

    private let fileURL: URL
    private let activeGroupKey = "stickyNotes.activeTabGroupID"
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = support.appendingPathComponent("StickyNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("groups.json")
        load()

        if let s = UserDefaults.standard.string(forKey: activeGroupKey),
           let uuid = UUID(uuidString: s),
           groups.contains(where: { $0.id == uuid }) {
            activeGroupID = uuid
        } else {
            activeGroupID = groups.first?.id
        }
    }

    // MARK: - Lookup

    func group(id: UUID) -> TabGroup? {
        groups.first { $0.id == id }
    }

    var activeGroup: TabGroup? {
        guard let id = activeGroupID else { return nil }
        return group(id: id)
    }

    func contains(_ url: String, group: TabGroup) -> Bool {
        group.urls.contains(Self.canonicalize(url))
    }

    func contains(_ url: String, groupID: UUID) -> Bool {
        guard let g = group(id: groupID) else { return false }
        return contains(url, group: g)
    }

    // MARK: - Mutation

    @discardableResult
    func create(name: String) -> TabGroup {
        let g = TabGroup(name: name)
        groups.append(g)
        setActive(g.id)
        scheduleSave()
        return g
    }

    func delete(id: UUID) {
        groups.removeAll { $0.id == id }
        if activeGroupID == id {
            setActive(groups.first?.id)
        }
        scheduleSave()
    }

    func rename(id: UUID, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = name
        groups[idx].updatedAt = Date()
        scheduleSave()
    }

    func addTab(_ url: String, to id: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        let canonical = Self.canonicalize(url)
        if !groups[idx].urls.contains(canonical) {
            groups[idx].urls.append(canonical)
            groups[idx].updatedAt = Date()
            setActive(id)
            scheduleSave()
        }
    }

    func removeTab(_ url: String, from id: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        let canonical = Self.canonicalize(url)
        groups[idx].urls.removeAll { $0 == canonical }
        groups[idx].updatedAt = Date()
        scheduleSave()
    }

    /// Toggle membership. Returns `true` if the tab is now in the group, `false`
    /// if it was removed.
    @discardableResult
    func toggleTab(_ url: String, in id: UUID) -> Bool {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return false }
        let canonical = Self.canonicalize(url)
        if groups[idx].urls.contains(canonical) {
            groups[idx].urls.removeAll { $0 == canonical }
            groups[idx].updatedAt = Date()
            scheduleSave()
            return false
        } else {
            groups[idx].urls.append(canonical)
            groups[idx].updatedAt = Date()
            setActive(id)
            scheduleSave()
            return true
        }
    }

    func setActive(_ id: UUID?) {
        activeGroupID = id
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: activeGroupKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeGroupKey)
        }
    }

    // MARK: - Canonicalize (matches PinManager)

    static func canonicalize(_ url: String) -> String {
        var s = url
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if let h = s.firstIndex(of: "#") { s = String(s[..<h]) }
        return s
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard !data.isEmpty else { return }
        do {
            groups = try JSONDecoder().decode([TabGroup].self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupted-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("StickyNotes: groups.json decode failed (\(error)). Backed up to \(backup.lastPathComponent).")
        }
    }

    private func scheduleSave() {
        // Notify observers (PinManager) immediately so visibility re-evaluates.
        NotificationCenter.default.post(name: .tabGroupStoreDidChange, object: nil)
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension Notification.Name {
    static let tabGroupStoreDidChange = Notification.Name("StickyNotes.tabGroupStoreDidChange")
}