import AppKit
import NotchClipCore
import SwiftUI

/// `NotchClip --snapshot out.png [history-folder] [--keyboard] [--query words] [--preview] [--ai thinking|writing|done|failed] [--stack]` renders the open panel to a PNG and quits.
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
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--query"), args.count > flag + 1 {
            model.query = args[flag + 1]
        }

        let size = NSSize(
            width: model.openSize.width + Layout.shadowMargin * 2,
            height: model.openSize.height + Layout.shadowMargin
        )
        applyMode(args, to: model)
        let view = NotchView(model: model, settings: SettingsStore())
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

    /// Puts the panel into the preview/AI/stack state named on the command line (for screenshots).
    private static func applyMode(_ args: [String], to model: NotchModel) {
        guard let first = model.items.first(where: { $0.workingText != nil }) ?? model.items.first else { return }
        if args.contains("--stack") {
            model.items.prefix(3).reversed().forEach(model.toggleStack)
        }
        if args.contains("--preview") {
            model.mode = .preview(model.items.first ?? first)
        }
        if let flag = args.firstIndex(of: "--ai"), args.count > flag + 1 {
            model.mode = .ai(first)
            model.aiProviderName = "Using ChatGPT plan"
            let sample = "Hi! Comment \"AGENT\" below and I'll send you the full prompt pack. 🔥"
            let status: AIRun.Status
            switch args[flag + 1] {
            case "thinking": status = .thinking
            case "writing": status = .writing(String(sample.prefix(30)))
            case "failed": status = .failed(AIError.usageLimit.localizedDescription)
            default: status = .done(sample)
            }
            model.aiRun = AIRun(item: first, action: .friendlier, status: status)
        }
    }
}
