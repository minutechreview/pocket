import AppKit
import NotchClipCore
import ServiceManagement

/// Wires the pieces together: history store, clipboard watcher, notch panel, shortcut and menu bar icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let pasteDelay: TimeInterval = 0.12

    private let store = ClipStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var model = NotchModel(store: store)
    private lazy var controller = NotchController(model: model)
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var askedForPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.model.reload() }
        }
        model.onPick = { [weak self] item in self?.pick(item) }
        model.onDelete = { [weak self] item in self?.store.remove(id: item.id) }

        controller.start()
        monitor.start()
        hotKey = HotKey(keyCode: HotKey.defaultKeyCode, modifiers: HotKey.defaultModifiers) { [weak self] in
            self?.controller.toggleFromShortcut()
        }
        setUpStatusItem()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.layout() }
        }
    }

    // MARK: Picking a clip

    private func pick(_ item: ClipItem) {
        guard let changeCount = PasteboardIO.write(item, store: store, to: .general) else {
            model.showToast("That clip couldn't be loaded")
            return
        }
        monitor.skip(changeCount: changeCount)
        store.promote(id: item.id)

        guard Paster.isAllowed else {
            // Without the Accessibility permission we can only copy; the user presses ⌘V.
            model.showToast("Copied! Press ⌘V to paste")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.controller.close() }
            if !askedForPermission {
                askedForPermission = true
                Paster.requestPermission()
            }
            return
        }
        controller.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) {
            Paster.pasteIntoFrontApp()
        }
    }

    // MARK: Menu bar icon

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "NotchClip")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openPanel() { controller.open(keyboard: true) }

    @objc private func enableAutoPaste() { Paster.requestPermission() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change “Open at Login”"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This removes all \(store.items.count) saved clips. It can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.removeAll()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt every time it opens so the permission and login states are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open Clipboard", action: #selector(openPanel), keyEquivalent: "c")
        open.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(open)
        menu.addItem(.separator())

        if Paster.isAllowed {
            menu.addItem(disabled("Auto-paste is on"))
        } else {
            menu.addItem(NSMenuItem(title: "Turn On Auto-paste…", action: #selector(enableAutoPaste), keyEquivalent: ""))
        }
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(disabled("\(store.items.count) clips saved"))
        menu.addItem(NSMenuItem(title: "Quit NotchClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.filter { $0.action != #selector(NSApplication.terminate(_:)) }.forEach { $0.target = self }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
