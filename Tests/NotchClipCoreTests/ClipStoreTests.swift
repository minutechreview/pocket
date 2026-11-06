import Foundation
import Testing
@testable import NotchClipCore

/// Each test gets its own temporary history folder.
struct ClipStoreTests {
    let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchClipTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStore(limit: Int = 50) -> ClipStore {
        ClipStore(directory: directory, limit: limit)
    }

    /// A tiny valid 4×3 PNG; the colour makes each one unique.
    private func png(red: UInt8) -> Data {
        PNGFixture.png(width: 4, height: 3, red: red)
    }

    @Test func newestTextComesFirst() {
        let store = makeStore()
        store.addText("first")
        store.addText("second")
        #expect(store.items.map(\.text) == ["second", "first"])
    }

    @Test func blankTextIsIgnored() {
        let store = makeStore()
        #expect(store.addText("   \n ") == nil)
        #expect(store.items.isEmpty)
    }

    @Test func copyingAgainMovesToTopWithoutDuplicate() {
        let store = makeStore()
        store.addText("a")
        store.addText("b")
        store.addText("a")
        #expect(store.items.map(\.text) == ["a", "b"])
    }

    @Test func historyIsCappedAtLimit() {
        let store = makeStore(limit: 3)
        (1...5).forEach { store.addText("item \($0)") }
        #expect(store.items.map(\.text) == ["item 5", "item 4", "item 3"])
    }

    @Test func historySurvivesRestart() {
        let source = ClipSource(name: "Notes", bundleID: "com.apple.Notes")
        makeStore().addText("kept", source: source)
        let reopened = makeStore()
        #expect(reopened.items.first?.text == "kept")
        #expect(reopened.items.first?.source == source)
    }

    @Test func imageIsSavedWithThumbnailAndSize() throws {
        let store = makeStore()
        let item = try #require(store.addImage(png: png(red: 200)))
        #expect(item.kind == .image)
        #expect(item.pixelWidth == 4 && item.pixelHeight == 3)
        let imageURL = try #require(store.imageURL(for: item))
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
        #expect(item.thumbFile != nil)
    }

    @Test func invalidImageDataIsRejected() {
        let store = makeStore()
        #expect(store.addImage(png: Data("not an image".utf8)) == nil)
    }

    @Test func removingAnImageDeletesItsFiles() throws {
        let store = makeStore()
        let item = try #require(store.addImage(png: png(red: 10)))
        let imageURL = try #require(store.imageURL(for: item))
        store.remove(id: item.id)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test func droppedOverflowImagesAreDeleted() throws {
        let store = makeStore(limit: 1)
        let old = try #require(store.addImage(png: png(red: 1)))
        let oldURL = try #require(store.imageURL(for: old))
        store.addText("newer")
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
    }

    @Test func promoteMovesItemToTop() throws {
        let store = makeStore()
        let first = try #require(store.addText("one"))
        store.addText("two")
        store.promote(id: first.id)
        #expect(store.items.map(\.text) == ["one", "two"])
    }

    @Test func clearRemovesEverything() {
        let store = makeStore()
        store.addText("x")
        store.removeAll()
        #expect(store.items.isEmpty)
        #expect(makeStore().items.isEmpty)
    }

    @Test func pinnedClipsComeFirstAndSurviveTheLimit() throws {
        let store = makeStore(limit: 2)
        let keep = try #require(store.addText("my email"))
        store.setPinned(true, id: keep.id)
        (1...4).forEach { store.addText("clip \($0)") }
        #expect(store.ordered.map(\.text) == ["my email", "clip 4", "clip 3"])
        #expect(makeStore(limit: 2).ordered.first?.pinned == true)
    }

    @Test func searchMatchesEveryWordIgnoringCase() {
        let store = makeStore()
        store.addText("Invoice for Kade, November")
        store.addText("kade logo colours")
        store.addText("Something else", source: ClipSource(name: "Safari", bundleID: nil))
        #expect(store.search("KADE invoice").map(\.text) == ["Invoice for Kade, November"])
        #expect(store.search("safari").count == 1)
        #expect(store.search("  ").count == 3)
    }

    @Test func searchFindsTextInsideScreenshots() throws {
        let store = makeStore()
        let shot = try #require(store.addImage(png: png(red: 90)))
        store.setOCRText("  Error 404: page not found \n", id: shot.id)
        #expect(store.search("404").map(\.id) == [shot.id])
        #expect(store.items.first?.ocrText == "Error 404: page not found")
    }

    @Test func oldHistoryWithoutNewFieldsStillLoads() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"[{"id":"9E0D2C55-1E5C-4C55-9A57-3D6F0C6A0B11","kind":"text","text":"old","hash":"t1","date":"2026-11-06T02:00:00Z"}]"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("history.json"))
        let item = try #require(makeStore().items.first)
        #expect(item.text == "old" && item.pinned == false && item.ocrText == nil)
    }

    @Test func autoDeleteKeepsPinnedAndRecentClips() throws {
        let store = makeStore()
        let now = Date()
        let old = try #require(store.addText("old", now: now.addingTimeInterval(-10 * 86_400)))
        let pinnedOld = try #require(store.addText("pinned old", now: now.addingTimeInterval(-10 * 86_400)))
        store.setPinned(true, id: pinnedOld.id)
        store.addText("new", now: now)
        #expect(store.prune(olderThan: 7 * 86_400, now: now) == 1)
        #expect(!store.items.contains { $0.id == old.id })
        #expect(Set(store.items.compactMap(\.text)) == ["pinned old", "new"])
    }

    @Test func loweringTheLimitDropsOldestClips() {
        let store = makeStore(limit: 10)
        (1...6).forEach { store.addText("clip \($0)") }
        store.setLimit(2)
        #expect(store.items.map(\.text) == ["clip 6", "clip 5"])
    }

    @Test func formattingIsSavedAndDeletedWithTheClip() throws {
        let store = makeStore()
        let item = try #require(store.addText("bold", rtf: Data("{\\rtf1 \\b bold}".utf8)))
        let url = try #require(store.richTextURL(for: item))
        #expect(FileManager.default.fileExists(atPath: url.path))
        store.remove(id: item.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func filesAreSavedAsPathsAndSearchable() throws {
        let store = makeStore()
        let item = try #require(store.addFiles(["/Users/me/Documents/Invoice March.pdf"]))
        #expect(item.kind == .file && item.fileNames == ["Invoice March.pdf"])
        #expect(store.search("invoice").map(\.id) == [item.id])
        #expect(store.addFiles([]) == nil)
    }

    @Test(arguments: [(10, "now"), (120, "2m"), (7200, "2h"), (172_800, "2d")])
    func relativeTimeLabels(seconds: Int, label: String) {
        let now = Date()
        #expect(RelativeTime.short(from: now.addingTimeInterval(-Double(seconds)), now: now) == label)
    }
}
