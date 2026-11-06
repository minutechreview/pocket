import AppKit
import NotchClipCore
import SwiftUI

/// A borderless panel that sits over the notch. It can take keyboard focus without
/// pulling the user's current app out of the front, so ⌘V still lands in that app.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a card count even though NotchClip is never the active app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Opens and closes the notch panel: on hover, on the shortcut, and after a pick.
@MainActor
final class NotchController {
    static let hoverOpenDelay: TimeInterval = 0.12
    static let closeAnimation: TimeInterval = 0.32
    static let mousePollInterval: TimeInterval = 1.0 / 30

    let model: NotchModel
    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var hoverStart: Date?
    private var mouseTimer: Timer?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(model: NotchModel, settings: SettingsStore) {
        self.model = model
        let host = FirstClickHostingView(rootView: NotchView(model: model, settings: settings))
        host.sizingOptions = []
        panel.contentView = host
    }

    func start() {
        layout()
        panel.orderFrontRegardless()
        startMousePolling()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, self.model.isOpen else { return event }
            return self.handleKey(event) ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.isSticky, self.model.isOpen else { return }
                self.close()
            }
        }
    }

    /// Re-measures the notch (call when displays change).
    func layout() {
        let target = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let target else { return }
        screen = target
        if let left = target.auxiliaryTopLeftArea, let right = target.auxiliaryTopRightArea, target.safeAreaInsets.top > 0 {
            model.hasNotch = true
            model.notchSize = CGSize(
                width: target.frame.width - left.width - right.width,
                height: target.safeAreaInsets.top
            )
        } else {
            model.hasNotch = false
            model.notchSize = CGSize(width: 220, height: 6)
        }
        panel.setFrame(model.isOpen ? openFrame : closedFrame, display: true)
    }

    // MARK: Open / close

    func toggleFromShortcut() {
        if model.isOpen && model.keyboardMode {
            close()
        } else {
            open(keyboard: true)
        }
    }

    func open(keyboard: Bool) {
        model.keyboardMode = keyboard
        if keyboard { model.selection = 0 }
        if keyboard {
            panel.makeKeyAndOrderFront(nil)
        }
        guard !model.isOpen else { return }
        panel.setFrame(openFrame, display: true)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { model.isOpen = true }
    }

    /// Gives the panel keyboard focus without bringing NotchClip to the front.
    func focusPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard model.isOpen else { return }
        model.query = ""
        model.backToClips()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { model.isOpen = false }
        model.keyboardMode = false
        giveFocusBack()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeAnimation) { [weak self] in
            guard let self, !self.model.isOpen else { return }
            self.panel.setFrame(self.closedFrame, display: true)
        }
    }

    /// Hands keyboard focus back to the app the user was in.
    private func giveFocusBack() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Geometry

    private var closedFrame: NSRect {
        guard let screen else { return .zero }
        let size = model.notchSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private var openFrame: NSRect {
        guard let screen else { return .zero }
        let size = model.openSize
        let width = size.width + Layout.shadowMargin * 2
        let height = size.height + Layout.shadowMargin
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    /// The black shape on screen (without the shadow margin), with a little slack.
    private var openShapeRect: NSRect {
        guard let screen else { return .zero }
        let size = model.openSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height).insetBy(dx: -8, dy: -10)
    }

    private var hotZone: NSRect {
        closedFrame.insetBy(dx: -6, dy: 0).union(closedFrame.offsetBy(dx: 0, dy: -2))
    }

    // MARK: Hover (polls the mouse position: works without any permission)

    private func startMousePolling() {
        let timer = Timer(timeInterval: Self.mousePollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func checkMouse() {
        let point = NSEvent.mouseLocation
        if model.isOpen {
            hoverStart = nil
            if !model.isSticky && !openShapeRect.contains(point) && NSEvent.pressedMouseButtons == 0 {
                close()
            }
            return
        }
        guard hotZone.contains(point) else {
            hoverStart = nil
            return
        }
        let start = hoverStart ?? Date()
        hoverStart = start
        if Date().timeIntervalSince(start) >= Self.hoverOpenDelay {
            hoverStart = nil
            open(keyboard: false)
        }
    }

    // MARK: Keyboard

    /// Keys in the preview and AI views: Esc goes back, Space closes the preview, ⌘Return pastes.
    private func handleDetailKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let inPreview: Bool = { if case .preview = model.mode { return true } else { return false } }()
        switch Int(event.keyCode) {
        case 53:
            model.backToClips()
            return true
        case 49 where inPreview:
            model.backToClips()
            return true
        case 36 where flags.contains(.command), 76 where flags.contains(.command):
            if case .done(let text) = model.aiRun?.status { model.onUseAIResult(text, true); return true }
            if case .preview(let item) = model.mode { model.onPick(item, false); return true }
            return false
        default:
            return false
        }
    }

    private static func arrowStep(_ keyCode: UInt16) -> Int {
        switch keyCode {
        case 123: return -1
        case 124: return 1
        case 126: return -Layout.columns
        default: return Layout.columns
        }
    }

    // Clip keys (only while the panel has focus)

    /// Typing goes to the search box; these keys drive the clips instead.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if model.mode != .clips { return handleDetailKey(event, flags: flags) }
        let command = flags.contains(.command)
        let selected = model.selectedItem
        switch Int(event.keyCode) {
        case 53:                                           // Esc: clear search, then the picked clips, then close
            if !model.query.isEmpty { model.query = "" } else if !model.stack.isEmpty { model.clearStack() } else { close() }
        case 36, 76 where !model.stack.isEmpty:            // Return with picked clips: paste them all, in order
            model.onPasteStack()
        case 36, 76:                                       // Return (⌥/⇧ = plain text / text from image)
            if let selected { model.onPick(selected, flags.contains(.shift) || flags.contains(.option)) }
        case 123...126 where flags.contains(.shift):       // ⇧ + arrows: pick several clips (⌃ + arrows switches Spaces)
            model.extendSelection(by: Self.arrowStep(event.keyCode))
        case 49 where model.query.isEmpty:                 // Space: big preview
            if let selected { model.showPreview(selected) }
        case 38 where command:                             // ⌘J: AI actions
            if let selected, selected.workingText != nil { model.showAI(selected) }
        case 1 where command:                              // ⌘S: add to / remove from paste stack
            if let selected { model.toggleStack(selected) }
        case 123: model.moveSelection(by: -1)              // ←
        case 124: model.moveSelection(by: 1)               // →
        case 126: model.moveSelection(by: -Layout.columns) // ↑
        case 125: model.moveSelection(by: Layout.columns)  // ↓
        case 51 where command, 117 where command:          // ⌘⌫ removes the clip
            if let selected { model.onDelete(selected) }
        case 35 where command:                             // ⌘P pins / unpins
            if let selected { model.onTogglePin(selected) }
        default:
            guard command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init) else {
                return false
            }
            let index = digit == 0 ? 9 : digit - 1          // ⌘1…⌘9, ⌘0 pastes that clip
            if model.items.indices.contains(index) { model.onPick(model.items[index], false) }
        }
        return true
    }
}
