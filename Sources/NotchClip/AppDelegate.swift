import AppKit
import NotchClipCore
import SwiftUI

/// Wires the pieces together: history store, clipboard watcher, notch panel, shortcuts, AI and the menu bar icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let pasteDelay: TimeInterval = 0.12
    static let pruneInterval: TimeInterval = 3600

    private let settings = SettingsStore()
    private lazy var store = ClipStore(limit: settings.value.historyLimit)
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var model = NotchModel(store: store)
    private lazy var controller = NotchController(model: model, settings: settings)
    private lazy var textReader = TextReader(store: store)
    private lazy var ai = AIService(settings: settings, model: model, store: store)
    private var openHotKey: HotKey?
    private var stackHotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var pruneTimer: Timer?
    private var askedForPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onChange = { [weak self] in
            MainActor.assumeIsolated {
                self?.model.reload()
                self?.textReader.readPending()
            }
        }
        wireModel()
        monitor.isIgnored = { [weak self] bundleID in self?.settings.value.ignores(bundleID: bundleID) ?? false }
        settings.onChange = { [weak self] old, new in self?.apply(old: old, new: new) }

        controller.start()
        monitor.start()
        textReader.readPending()
        registerHotKeys()
        setUpStatusItem()
        startPruning()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.layout() }
        }
    }

    private func wireModel() {
        model.onPick = { [weak self] item, plain in self?.pick(item, plain: plain) }
        model.onDelete = { [weak self] item in self?.store.remove(id: item.id) }
        model.onTogglePin = { [weak self] item in self?.store.setPinned(!item.pinned, id: item.id) }
        model.onPasteStack = { [weak self] in self?.pasteWholeStack() }
        model.onRunAI = { [weak self] item, action in self?.ai.run(action, on: item) }
        model.onCancelAI = { [weak self] in self?.ai.cancel() }
        model.onUseAIResult = { [weak self] text, paste in self?.useAIResult(text, paste: paste) }
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onNeedsFocus = { [weak self] in self?.controller.focusPanel() }
        model.aiProviderName = ai.providerName
    }

    // MARK: Settings changes

    private func apply(old: AppSettings, new: AppSettings) {
        if old.historyLimit != new.historyLimit { store.setLimit(new.historyLimit) }
        if old.autoDeleteDays != new.autoDeleteDays { prune() }
        if old.openShortcut != new.openShortcut || old.stackShortcut != new.stackShortcut { registerHotKeys() }
        if old.aiProvider != new.aiProvider || old.aiModel != new.aiModel {
            ai.forgetModelCache()
            model.aiProviderName = ai.providerName
        }
    }

    private func registerHotKeys() {
        openHotKey = nil
        stackHotKey = nil
        let value = settings.value
        openHotKey = HotKey(keyCode: value.openShortcut.keyCode, modifiers: value.openShortcut.modifiers, id: 1) { [weak self] in
            self?.controller.toggleFromShortcut()
        }
        stackHotKey = HotKey(keyCode: value.stackShortcut.keyCode, modifiers: value.stackShortcut.modifiers, id: 2) { [weak self] in
            self?.pasteNextFromStack()
        }
    }

    private func startPruning() {
        prune()
        let timer = Timer(timeInterval: Self.pruneInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    private func prune() {
        let days = settings.value.autoDeleteDays
        guard days > 0 else { return }
        store.prune(olderThan: TimeInterval(days) * 86_400)
    }

    // MARK: Pasting

    private func pick(_ item: ClipItem, plain: Bool) {
        let changeCount: Int?
        if plain, let text = item.workingText {
            changeCount = PasteboardIO.write(text: text, to: .general)
        } else if plain, item.kind == .image {
            model.showToast("No text found in this image")
            return
        } else {
            changeCount = PasteboardIO.write(item, store: store, keepFormatting: settings.value.keepFormatting, to: .general)
        }
        guard let changeCount else {
            model.showToast(item.kind == .file ? "That file has moved or been deleted" : "That clip couldn't be loaded")
            return
        }
        monitor.skip(changeCount: changeCount)
        if !item.pinned { store.promote(id: item.id) }
        pasteAndClose()
    }

    /// Closes the panel and sends ⌘V, or explains how to turn that on.
    private func pasteAndClose() {
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

    private func useAIResult(_ text: String, paste: Bool) {
        if paste {
            guard let changeCount = PasteboardIO.write(text: text, to: .general) else { return }
            monitor.skip(changeCount: changeCount)
            store.addText(text, source: ClipSource(name: "NotchClip AI", bundleID: nil))
            pasteAndClose()
        } else {
            // Copy: goes on the clipboard and into history like any other copy.
            _ = PasteboardIO.write(text: text, to: .general)
            model.showToast("Copied")
        }
    }

    /// The stack shortcut: pastes the next queued clip without opening the panel.
    private func pasteNextFromStack() {
        guard let item = model.popStack() else {
            model.showToast("Paste stack is empty. ⌘-click clips to add them.")
            controller.open(keyboard: false)
            return
        }
        guard let changeCount = PasteboardIO.write(item, store: store, keepFormatting: settings.value.keepFormatting, to: .general) else { return }
        monitor.skip(changeCount: changeCount)
        if Paster.isAllowed {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) { Paster.pasteIntoFrontApp() }
        }
    }

    /// "Paste all": every stacked clip's text joined by new lines, pasted at once.
    private func pasteWholeStack() {
        let texts = model.stackedItems.compactMap(\.workingText)
        guard !texts.isEmpty, let changeCount = PasteboardIO.write(text: texts.joined(separator: "\n"), to: .general) else {
            model.showToast("Only text clips can be pasted together")
            return
        }
        monitor.skip(changeCount: changeCount)
        model.clearStack()
        pasteAndClose()
    }

    // MARK: Windows and menu

    func openSettings() {
        controller.close()
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] in self?.confirmClearHistory() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "NotchClip Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This removes all \(store.items.count) saved clips, including pinned ones. It can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.removeAll()
        }
    }

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
    @objc private func settingsAction() { openSettings() }
    @objc private func clearHistoryAction() { confirmClearHistory() }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt every time it opens so the permission state is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "Open Clipboard  \(settings.value.openShortcut.label)", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        if Paster.isAllowed {
            menu.addItem(NSMenuItem(title: "Auto-paste is on", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Turn On Auto-paste…", action: #selector(enableAutoPaste), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Clear History…", action: #selector(clearHistoryAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "\(store.items.count) clips saved", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit NotchClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.filter { $0.action != #selector(NSApplication.terminate(_:)) && $0.action != nil }.forEach { $0.target = self }
    }
}
