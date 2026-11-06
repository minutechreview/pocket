import AppKit
import NotchClipCore
import SwiftUI

/// Sizes for the open panel. Five cards per row, two rows visible, so the last 10 copies show at once.
enum Layout {
    static let columns = 5
    static let cardWidth: CGFloat = 138
    static let cardHeight: CGFloat = 116
    static let gap: CGFloat = 10
    static let sidePadding: CGFloat = 14
    static let bottomPadding: CGFloat = 14
    static let shadowMargin: CGFloat = 36
    static let openRadius: CGFloat = 24
    static let closedRadius: CGFloat = 10

    static var openWidth: CGFloat {
        CGFloat(columns) * cardWidth + CGFloat(columns - 1) * gap + sidePadding * 2
    }

    static func openHeight(headerHeight: CGFloat) -> CGFloat {
        headerHeight + 2 * cardHeight + gap + bottomPadding + 6
    }
}

/// Everything the SwiftUI panel shows. The controller owns the behaviour.
@MainActor
final class NotchModel: ObservableObject {
    @Published var isOpen = false
    @Published var items: [ClipItem] = []
    @Published var selection = 0
    @Published var keyboardMode = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = true
    @Published var toast: String?

    var onPick: (ClipItem) -> Void = { _ in }
    var onDelete: (ClipItem) -> Void = { _ in }

    private let store: ClipStore
    private var thumbnails: [UUID: NSImage] = [:]
    private var appIcons: [String: NSImage] = [:]

    init(store: ClipStore) {
        self.store = store
        self.items = store.items
    }

    var headerHeight: CGFloat { max(notchSize.height, 28) }
    var openSize: CGSize { CGSize(width: Layout.openWidth, height: Layout.openHeight(headerHeight: headerHeight)) }

    func reload() {
        items = store.items
        let ids = Set(items.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        selection = min(selection, max(0, items.count - 1))
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let url = store.thumbnailURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        thumbnails[item.id] = image
        return image
    }

    func appIcon(for item: ClipItem) -> NSImage? {
        guard let bundleID = item.source?.bundleID else { return nil }
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(0, selection + delta), items.count - 1)
    }

    func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard self?.toast == text else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }
}
