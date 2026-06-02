import AppKit

#if canImport(SwiftMath)
import SwiftMath
#endif

// MARK: - Math renderer

/// Renders LaTeX source to an NSImage using SwiftMath. If SwiftMath isn't
/// installed (no SPM dependency added yet), every call returns nil — math
/// blocks then stay as raw `$$...$$` text. Add the package to enable rendering.
enum MathRenderer {
    private static var cache: [String: NSImage] = [:]
    private static let cacheLimit = 200

    static func render(latex: String, fontSize: CGFloat = 18) -> NSImage? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cacheKey = "\(fontSize)|\(trimmed)"
        if let cached = cache[cacheKey] { return cached }

        #if canImport(SwiftMath)
        let mathImage = MTMathImage(
            latex: trimmed,
            fontSize: fontSize,
            textColor: .black,
            labelMode: .display
        )
        // SwiftMath's asImage() returns (MTRenderError?, NSImage?) on macOS.
        let result = mathImage.asImage()
        if let err = result.0 {
            NSLog("StickyNotes: math render error for [\(trimmed)]: \(err)")
            return nil
        }
        guard let image = result.1 else { return nil }

        if cache.count > cacheLimit { cache.removeAll() }
        cache[cacheKey] = image
        return image
        #else
        return nil
        #endif
    }
}

// MARK: - Persistable attachment

/// An NSTextAttachment that remembers its LaTeX source so we can revert to raw
/// text for editing. The source is encoded into the file wrapper's filename so
/// it survives a save/load round trip through RTFD.
final class MathAttachment: NSTextAttachment {
    var latexSource: String = ""

    convenience init(source: String, image: NSImage) {
        self.init()
        self.latexSource = source
        self.image = image
        self.bounds = NSRect(origin: .zero, size: image.size)

        // Persist the source by piggybacking on the file wrapper's filename.
        // RTFD includes the file wrapper in the saved bundle; on load, we can
        // recover the source by parsing the filename.
        if let png = image.pngRepresentation() {
            let fw = FileWrapper(regularFileWithContents: png)
            fw.preferredFilename = Self.filename(forSource: source)
            self.fileWrapper = fw
        }
    }

    static let filenamePrefix = "math__"
    static let filenameSuffix = ".png"

    static func filename(forSource source: String) -> String {
        // URL-safe base64 with our own padding char so it's filename-safe.
        let b64 = Data(source.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "~")
        return filenamePrefix + b64 + filenameSuffix
    }

    static func sourceFromFilename(_ filename: String) -> String? {
        guard filename.hasPrefix(filenamePrefix),
              filename.hasSuffix(filenameSuffix) else { return nil }
        let middle = filename
            .dropFirst(filenamePrefix.count)
            .dropLast(filenameSuffix.count)
        var b64 = String(middle)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "~", with: "=")
        let padding = (4 - b64.count % 4) % 4
        b64 += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: b64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// After loading an RTFD into an NSAttributedString, walk it and re-instate
    /// any MathAttachments whose filename matches our pattern. Plain attachments
    /// (regular pasted images) are left untouched.
    static func upgradeAttachments(in attributedString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var replacements: [(NSRange, MathAttachment)] = []

        attributedString.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  !(attachment is MathAttachment),
                  let filename = attachment.fileWrapper?.preferredFilename,
                  let source = sourceFromFilename(filename),
                  let data = attachment.fileWrapper?.regularFileContents,
                  let image = NSImage(data: data) else { return }

            let math = MathAttachment(source: source, image: image)
            replacements.append((range, math))
        }

        for (range, math) in replacements.reversed() {
            attributedString.replaceCharacters(in: range,
                                               with: NSAttributedString(attachment: math))
        }
    }
}

// MARK: - NSImage helpers

extension NSImage {
    func pngRepresentation() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
