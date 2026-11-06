import AppKit
import NotchClipCore

/// Watches the system clipboard and records every new copy in the store.
/// macOS has no "clipboard changed" event, so this checks the change counter a few times a second.
@MainActor
final class ClipboardMonitor {
    static let interval: TimeInterval = 0.4

    private let store: ClipStore
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Returns true for apps whose copies should never be saved (password managers, banking…).
    var isIgnored: (String?) -> Bool = { _ in false }

    init(store: ClipStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Call after NotchClip itself writes to the clipboard, so that write isn't recorded as a new copy.
    func skip(changeCount: Int) {
        lastChangeCount = changeCount
    }

    private func check() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let app = NSWorkspace.shared.frontmostApplication
        guard !isIgnored(app?.bundleIdentifier), let content = PasteboardIO.read(pasteboard) else { return }
        let source = app.map { ClipSource(name: $0.localizedName ?? "App", bundleID: $0.bundleIdentifier) }
        switch content {
        case .text(let text, let rtf):
            store.addText(text, rtf: rtf, source: source)
        case .image(let png):
            store.addImage(png: png, source: source)
        case .files(let paths):
            store.addFiles(paths, source: source)
        }
    }
}
