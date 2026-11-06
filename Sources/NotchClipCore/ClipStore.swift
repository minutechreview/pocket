import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Clipboard history kept on disk: `history.json` plus PNGs in `images/`.
/// Newest item first. Copying something already in the history moves it back to the top.
public final class ClipStore {
    public static let defaultLimit = 50
    public static let maxTextLength = 1_000_000
    public static let thumbnailPixels = 360

    public private(set) var items: [ClipItem] = []
    public let directory: URL
    public let limit: Int
    public var onChange: (() -> Void)?

    private let fileManager = FileManager.default

    public init(directory: URL = ClipStore.defaultDirectory(), limit: Int = ClipStore.defaultLimit) {
        self.directory = directory
        self.limit = max(1, limit)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        items = loadIndex()
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchClip", isDirectory: true)
    }

    public var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("history.json") }

    public func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    public func thumbnailURL(for item: ClipItem) -> URL? {
        (item.thumbFile ?? item.imageFile).map { imagesDirectory.appendingPathComponent($0) }
    }

    // MARK: Adding

    /// Adds copied text. Blank text and text over `maxTextLength` are ignored.
    @discardableResult
    public func addText(_ text: String, source: ClipSource? = nil, now: Date = Date()) -> ClipItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= Self.maxTextLength else { return nil }
        let hash = Self.digest(Data(text.utf8), prefix: "t")
        if let existing = bringToTop(hash: hash, now: now) { return existing }
        return insert(ClipItem(kind: .text, text: text, hash: hash, date: now, source: source))
    }

    /// Adds a copied image given as PNG data. Writes the PNG and a small thumbnail to disk.
    @discardableResult
    public func addImage(png: Data, source: ClipSource? = nil, now: Date = Date()) -> ClipItem? {
        guard let size = Self.pixelSize(of: png) else { return nil }
        let hash = Self.digest(png, prefix: "i")
        if let existing = bringToTop(hash: hash, now: now) { return existing }

        let id = UUID()
        let imageName = "\(id.uuidString).png"
        do {
            try png.write(to: imagesDirectory.appendingPathComponent(imageName), options: .atomic)
        } catch {
            return nil
        }
        var thumbName: String?
        if let thumb = Self.thumbnail(of: png, maxPixels: Self.thumbnailPixels) {
            let name = "\(id.uuidString)-thumb.png"
            if (try? thumb.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)) != nil {
                thumbName = name
            }
        }
        return insert(ClipItem(
            id: id, kind: .image, imageFile: imageName, thumbFile: thumbName,
            pixelWidth: size.width, pixelHeight: size.height, hash: hash, date: now, source: source
        ))
    }

    // MARK: Editing

    /// Moves an item to the top (after it was pasted again).
    public func promote(id: UUID, now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index].touched(at: now)
        items = [item] + items.enumerated().filter { $0.offset != index }.map(\.element)
        save()
    }

    public func setPinned(_ pinned: Bool, id: UUID) {
        replace(id: id) { $0.with(pinned: pinned) }
    }

    /// Stores text read from an image. An empty string means "read, but no text found".
    public func setOCRText(_ text: String, id: UUID) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        replace(id: id) { $0.with(ocrText: cleaned) }
    }

    /// Pinned clips first (newest first), then the rest, newest first.
    public var ordered: [ClipItem] {
        items.filter(\.pinned) + items.filter { !$0.pinned }
    }

    /// Clips whose text, screenshot text or app name contain every word of `query`.
    public func search(_ query: String) -> [ClipItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return ordered }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return ordered.filter { item in
            let haystack = item.searchableText
            return words.allSatisfy { haystack.range(of: $0, options: options) != nil }
        }
    }

    public func remove(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        deleteFiles(of: item)
        items = items.filter { $0.id != id }
        save()
    }

    public func removeAll() {
        items.forEach(deleteFiles)
        items = []
        save()
    }

    // MARK: Internals

    private func bringToTop(hash: String, now: Date) -> ClipItem? {
        guard let existing = items.first(where: { $0.hash == hash }) else { return nil }
        promote(id: existing.id, now: now)
        return items.first
    }

    private func insert(_ item: ClipItem) -> ClipItem {
        let all = [item] + items
        // The limit counts unpinned clips only; pinned ones are kept until unpinned.
        let overflow = Set(all.filter { !$0.pinned }.dropFirst(limit).map(\.id))
        all.filter { overflow.contains($0.id) }.forEach(deleteFiles)
        items = all.filter { !overflow.contains($0.id) }
        save()
        return item
    }

    private func replace(id: UUID, _ change: (ClipItem) -> ClipItem) {
        guard items.contains(where: { $0.id == id }) else { return }
        items = items.map { $0.id == id ? change($0) : $0 }
        save()
    }

    private func deleteFiles(of item: ClipItem) {
        [item.imageFile, item.thumbFile].compactMap { $0 }.forEach {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent($0))
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
        onChange?()
    }

    private func loadIndex() -> [ClipItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? decoder.decode([ClipItem].self, from: data) else { return [] }
        // Drop image clips whose file has gone missing.
        let present = saved.filter { item in
            guard let url = imageURL(for: item) else { return true }
            return fileManager.fileExists(atPath: url.path)
        }
        let keptUnpinned = Set(present.filter { !$0.pinned }.prefix(limit).map(\.id))
        return present.filter { $0.pinned || keptUnpinned.contains($0.id) }
    }

    // MARK: Helpers

    static func digest(_ data: Data, prefix: String) -> String {
        prefix + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func pixelSize(of imageData: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    static func thumbnail(of imageData: Data, maxPixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
