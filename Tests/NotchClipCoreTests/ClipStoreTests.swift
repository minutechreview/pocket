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

    @Test(arguments: [(10, "now"), (120, "2m"), (7200, "2h"), (172_800, "2d")])
    func relativeTimeLabels(seconds: Int, label: String) {
        let now = Date()
        #expect(RelativeTime.short(from: now.addingTimeInterval(-Double(seconds)), now: now) == label)
    }
}
