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

/// What the open panel is showing.
enum PanelMode: Equatable {
    case clips
    case preview(ClipItem)
    case ai(ClipItem)
}

/// An AI request shown in the panel.
struct AIRun: Equatable {
    enum Status: Equatable {
        case thinking
        case writing(String)
        case done(String)
        case failed(String)
    }

    let id = UUID()
    let item: ClipItem
    let action: AIAction
    var status: Status

    var output: String? {
        switch status {
        case .writing(let text), .done(let text): return text
        default: return nil
        }
    }
}

/// Everything the SwiftUI panel shows. The controller and app delegate own the behaviour.
@MainActor
final class NotchModel: ObservableObject {
    @Published var isOpen = false
    @Published var items: [ClipItem] = []
    @Published var selection = 0
    @Published var keyboardMode = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = true
    @Published var toast: String?
    @Published var mode = PanelMode.clips
    @Published var aiRun: AIRun?
    @Published var aiProviderName = ""
    /// Clips queued with ⌘-click, pasted one by one with the stack shortcut.
    @Published private(set) var stack: [UUID] = []
    /// Search box text. Changing it filters the clips.
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            selection = 0
            refilter()
        }
    }

    /// Paste a clip. `plain` drops formatting; for images it pastes the text read from the image.
    var onPick: (ClipItem, _ plain: Bool) -> Void = { _, _ in }
    var onPasteStack: () -> Void = {}
    var onDelete: (ClipItem) -> Void = { _ in }
    var onTogglePin: (ClipItem) -> Void = { _ in }
    var onRunAI: (ClipItem, AIAction) -> Void = { _, _ in }
    var onUseAIResult: (String, _ paste: Bool) -> Void = { _, _ in }
    var onCancelAI: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Asks the controller to give the panel keyboard focus (for typing in the AI box).
    var onNeedsFocus: () -> Void = {}

    private let store: ClipStore
    private var thumbnails: [UUID: NSImage] = [:]
    private var appIcons: [String: NSImage] = [:]

    init(store: ClipStore) {
        self.store = store
        self.items = store.ordered
    }

    var headerHeight: CGFloat { max(notchSize.height, 28) }
    var openSize: CGSize { CGSize(width: Layout.openWidth, height: Layout.openHeight(headerHeight: headerHeight)) }
    /// While true, moving the mouse away does not close the panel.
    var isSticky: Bool { keyboardMode || mode != .clips }

    func reload() {
        refilter()
        let ids = Set(store.items.map(\.id))
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        stack = stack.filter(ids.contains)
    }

    private func refilter() {
        items = store.search(query)
        selection = min(selection, max(0, items.count - 1))
    }

    var selectedItem: ClipItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let url = store.thumbnailURL(for: item), let image = NSImage(contentsOf: url) else { return nil }
        thumbnails[item.id] = image
        return image
    }

    func imageFileURL(for item: ClipItem) -> URL? {
        store.imageURL(for: item)
    }

    func fullImage(for item: ClipItem) -> NSImage? {
        store.imageURL(for: item).flatMap(NSImage.init(contentsOf:))
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

    // MARK: Paste stack

    func stackPosition(of item: ClipItem) -> Int? {
        stack.firstIndex(of: item.id).map { $0 + 1 }
    }

    func toggleStack(_ item: ClipItem) {
        withAnimation(.snappy(duration: 0.15)) {
            stack = stack.contains(item.id) ? stack.filter { $0 != item.id } : stack + [item.id]
        }
    }

    func clearStack() {
        withAnimation(.snappy(duration: 0.15)) { stack = [] }
    }

    /// Takes the next clip off the stack.
    func popStack() -> ClipItem? {
        while let first = stack.first {
            stack = Array(stack.dropFirst())
            if let item = store.items.first(where: { $0.id == first }) { return item }
        }
        return nil
    }

    var stackedItems: [ClipItem] {
        stack.compactMap { id in store.items.first { $0.id == id } }
    }

    // MARK: Modes

    func showPreview(_ item: ClipItem) {
        withAnimation(.snappy(duration: 0.2)) { mode = .preview(item) }
    }

    func showAI(_ item: ClipItem) {
        aiRun = nil
        withAnimation(.snappy(duration: 0.2)) { mode = .ai(item) }
        onNeedsFocus()
    }

    func backToClips() {
        if aiRun?.status == .thinking { onCancelAI() }
        if case .writing = aiRun?.status { onCancelAI() }
        aiRun = nil
        withAnimation(.snappy(duration: 0.2)) { mode = .clips }
    }

    func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard self?.toast == text else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }
}
