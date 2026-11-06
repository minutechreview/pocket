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

/// One entry in the clipboard history. Images live on disk; the item only names the files.
public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
    }

    public let id: UUID
    public let kind: Kind
    public let text: String?
    public let imageFile: String?
    public let thumbFile: String?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let hash: String
    public let date: Date
    public let source: ClipSource?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        text: String? = nil,
        imageFile: String? = nil,
        thumbFile: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        hash: String,
        date: Date = Date(),
        source: ClipSource? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.thumbFile = thumbFile
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hash = hash
        self.date = date
        self.source = source
    }

    /// A copy of this item stamped with a new date (used when an old clip is copied again).
    public func touched(at date: Date) -> ClipItem {
        ClipItem(
            id: id, kind: kind, text: text, imageFile: imageFile, thumbFile: thumbFile,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, hash: hash, date: date, source: source
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
