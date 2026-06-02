import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String           // plain-text view (used for previews/search)
    var contentRTFD: Data?        // rich text + embedded images (RTFD)
    var createdAt: Date
    var updatedAt: Date
    var color: NoteColor
    var kind: NoteKind
    var pinnedToApp: String?      // bundle ID of the app this note is pinned to
    var pinnedToURL: String?      // optional URL (for Chrome tab-specific pinning)
    var pinMatchMode: PinMatchMode?  // how to compare pinned URL against current URL
    var pinnedGroupID: UUID?      // for .group match mode — which TabGroup
    var strokes: [Stroke]         // legacy field, kept for backwards compat
    var frameX: Double?
    var frameY: Double?
    var frameW: Double?
    var frameH: Double?
    /// User explicitly closed (X) this note. Persists across launches and peek
    /// toggles. Cleared when the user opens the note again via history.
    var dismissed: Bool

    init(content: String = "", color: NoteColor = .yellow, kind: NoteKind = .text) {
        self.id = UUID()
        self.content = content
        self.contentRTFD = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.color = color
        self.kind = kind
        self.pinnedToApp = nil
        self.pinnedToURL = nil
        self.pinMatchMode = nil
        self.pinnedGroupID = nil
        self.strokes = []
        self.dismissed = false
    }

    // Backwards-compatible decoding: old notes don't have the new fields.
    enum CodingKeys: String, CodingKey {
        case id, content, contentRTFD, createdAt, updatedAt
        case color, kind, pinnedToApp, pinnedToURL, pinMatchMode, pinnedGroupID, strokes
        case frameX, frameY, frameW, frameH
        case dismissed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,   forKey: .id)
        content      = try c.decode(String.self, forKey: .content)
        contentRTFD  = try c.decodeIfPresent(Data.self,   forKey: .contentRTFD)
        createdAt    = try c.decode(Date.self,   forKey: .createdAt)
        updatedAt    = try c.decode(Date.self,   forKey: .updatedAt)
        color        = try c.decode(NoteColor.self, forKey: .color)
        kind         = try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .text
        pinnedToApp  = try c.decodeIfPresent(String.self, forKey: .pinnedToApp)
        pinnedToURL  = try c.decodeIfPresent(String.self, forKey: .pinnedToURL)
        pinMatchMode = try c.decodeIfPresent(PinMatchMode.self, forKey: .pinMatchMode)
        pinnedGroupID = try c.decodeIfPresent(UUID.self, forKey: .pinnedGroupID)
        strokes      = try c.decodeIfPresent([Stroke].self, forKey: .strokes) ?? []
        frameX       = try c.decodeIfPresent(Double.self, forKey: .frameX)
        frameY       = try c.decodeIfPresent(Double.self, forKey: .frameY)
        frameW       = try c.decodeIfPresent(Double.self, forKey: .frameW)
        frameH       = try c.decodeIfPresent(Double.self, forKey: .frameH)
        dismissed    = try c.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
    }

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return kind == .whiteboard ? "Whiteboard" : "Empty note"
    }

    var firstLine: String {
        let line = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if !line.isEmpty { return line }
        return kind == .whiteboard ? "Whiteboard" : ""
    }
}

enum NoteKind: String, Codable {
    case text
    case whiteboard
}

/// How a Chrome URL-pinned note matches the current Chrome tab.
enum PinMatchMode: String, Codable {
    case tab    // canonical URL match (path-level — ignores `?query` and `#hash`)
    case host   // any URL on the same host (e.g. all docs.google.com tabs)
    case group  // any URL in a user-defined TabGroup
}

// MARK: - Drawing strokes (for whiteboard notes)

struct Stroke: Codable, Equatable {
    var points: [StrokePoint]
    var colorHex: String
    var width: Double
}

struct StrokePoint: Codable, Equatable {
    var x: Double
    var y: Double
}

// MARK: - Colors

enum NoteColor: String, Codable, CaseIterable {
    case yellow, pink, orange, green, blue, purple, gray

    var hex: (light: String, dark: String) {
        switch self {
        case .yellow: return ("#FFF780", "#4A4519")
        case .pink:   return ("#FFC4D1", "#4A2530")
        case .orange: return ("#FFCE9B", "#4A3318")
        case .green:  return ("#CFEE9F", "#2B4019")
        case .blue:   return ("#B6DEF6", "#1F3349")
        case .purple: return ("#DBC1E8", "#3A2845")
        case .gray:   return ("#EAEAEA", "#2A2A2A")
        }
    }

    var displayName: String { rawValue.capitalized }

    /// Highlighter color for text in this note. Yellow normally;
    /// if the note IS yellow, fall back to a contrasting cyan-blue.
    var highlightHex: String {
        switch self {
        case .yellow: return "#A8E0FF"   // light cyan, readable on yellow bg
        default:      return "#FFEC60"   // canary yellow
        }
    }

    // Tracks the last randomly picked color so we don't pick it again immediately.
    private static var lastRandom: NoteColor?

    static var random: NoteColor {
        let pool = allCases.filter { $0 != .gray && $0 != lastRandom }
        let picked = pool.randomElement()
            ?? allCases.first(where: { $0 != .gray })
            ?? .yellow
        lastRandom = picked
        return picked
    }
}
