import Foundation

/// The app a clip was copied from.
public struct ClipSource: Codable, Equatable, Sendable {
    public let name: String
    public let bundleID: String?

    public init(name: String, bundleID: String?) {
        self.name = name
        self.bundleID = bundleID
    }
}

/// One entry in the clipboard history. Images and formatting live on disk; the item only names the files.
public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
        case file
    }

    public let id: UUID
    public let kind: Kind
    public let text: String?
    public let imageFile: String?
    public let thumbFile: String?
    /// Formatting (RTF) saved next to the plain text, so a paste keeps bold, links and fonts.
    public let richFile: String?
    /// Copied Finder files (absolute paths).
    public let filePaths: [String]?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let hash: String
    public let date: Date
    public let source: ClipSource?
    /// Pinned clips stay at the front and are never dropped when history is full.
    public let pinned: Bool
    /// Text read out of an image clip (screenshots), used for search and "copy text".
    public let ocrText: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        text: String? = nil,
        imageFile: String? = nil,
        thumbFile: String? = nil,
        richFile: String? = nil,
        filePaths: [String]? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        hash: String,
        date: Date = Date(),
        source: ClipSource? = nil,
        pinned: Bool = false,
        ocrText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.thumbFile = thumbFile
        self.richFile = richFile
        self.filePaths = filePaths
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hash = hash
        self.date = date
        self.source = source
        self.pinned = pinned
        self.ocrText = ocrText
    }

    /// Reads history saved by older versions, which lacked the newer optional fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        thumbFile = try c.decodeIfPresent(String.self, forKey: .thumbFile)
        richFile = try c.decodeIfPresent(String.self, forKey: .richFile)
        filePaths = try c.decodeIfPresent([String].self, forKey: .filePaths)
        pixelWidth = try c.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decodeIfPresent(Int.self, forKey: .pixelHeight)
        hash = try c.decode(String.self, forKey: .hash)
        date = try c.decode(Date.self, forKey: .date)
        source = try c.decodeIfPresent(ClipSource.self, forKey: .source)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
    }

    /// A copy of this item stamped with a new date (used when an old clip is copied again).
    public func touched(at date: Date) -> ClipItem { copy(date: date) }

    public func with(pinned: Bool) -> ClipItem { copy(pinned: pinned) }

    public func with(ocrText: String?) -> ClipItem { copy(ocrText: .some(ocrText)) }

    /// True when text was found in this image clip.
    public var hasReadableText: Bool { !(ocrText ?? "").isEmpty }

    /// The text an action (AI, paste as text) works on: the clip's own text or the screenshot's text.
    public var workingText: String? {
        if let text, !text.isEmpty { return text }
        return hasReadableText ? ocrText : nil
    }

    /// File names for file clips, e.g. "Invoice.pdf".
    public var fileNames: [String] {
        (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
    }

    /// Everything search looks at.
    public var searchableText: String {
        ([text, ocrText, source?.name].compactMap { $0 } + fileNames).joined(separator: "\n")
    }

    /// Every file on disk this clip owns.
    var ownedFiles: [String] { [imageFile, thumbFile, richFile].compactMap { $0 } }

    private func copy(date: Date? = nil, pinned: Bool? = nil, ocrText: String?? = nil) -> ClipItem {
        ClipItem(
            id: id, kind: kind, text: text, imageFile: imageFile, thumbFile: thumbFile,
            richFile: richFile, filePaths: filePaths, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            hash: hash, date: date ?? self.date, source: source,
            pinned: pinned ?? self.pinned, ocrText: ocrText ?? self.ocrText
        )
    }
}

/// Short "time ago" labels for cards: "now", "5m", "3h", "2d".
public enum RelativeTime {
    public static func short(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<45: return "now"
        case ..<3600: return "\(max(1, seconds / 60))m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}
