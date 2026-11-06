import AppKit
import NotchClipCore
import SwiftUI

/// `NotchClip --snapshot out.png [history-folder]` renders the open panel to a PNG and quits.
/// Used to check the design and make screenshots without screen-recording access.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), args.count > flag + 1 else { return false }
        let output = URL(fileURLWithPath: args[flag + 1])
        let directory = args.count > flag + 2 ? URL(fileURLWithPath: args[flag + 2]) : ClipStore.defaultDirectory()
        let keyboard = args.contains("--keyboard")
        render(store: ClipStore(directory: directory), to: output, keyboard: keyboard)
        return true
    }

    private static func render(store: ClipStore, to output: URL, keyboard: Bool) {
        let model = NotchModel(store: store)
        model.notchSize = CGSize(width: 200, height: 37)
        model.isOpen = true
        model.keyboardMode = keyboard
        model.selection = keyboard ? 1 : 0

        let size = NSSize(
            width: model.openSize.width + Layout.shadowMargin * 2,
            height: model.openSize.height + Layout.shadowMargin
        )
        let view = NotchView(model: model)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.82))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: output)
        }
    }
}
