import AppKit
import NotchClipCore

/// Demo mode: a separate, clean history filled with good-looking sample copies, for screen recordings.
/// Your real history is left alone; turning demo mode off brings it back.
@MainActor
enum DemoMode {
    private static let key = "demoMode"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static var directory: URL {
        ClipStore.defaultDirectory().deletingLastPathComponent().appendingPathComponent("Pocket Demo", isDirectory: true)
    }

    private static var filesDirectory: URL { directory.appendingPathComponent("Files", isDirectory: true) }

    /// Flips the switch and relaunches, so the app opens on the other history.
    static func toggle() {
        UserDefaults.standard.set(!isOn, forKey: key)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        let url = Bundle.main.bundleURL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
            NSApp.terminate(nil)
        }
    }

    /// Fills an empty demo history. Oldest first, so the last one added sits at the top.
    static func seedIfEmpty(_ store: ClipStore) {
        guard store.items.isEmpty else { return }
        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let files = makeFiles()
        var time = Date().addingTimeInterval(-3 * 3600)
        func next() -> Date { time = time.addingTimeInterval(540); return time }
        func src(_ name: String, _ id: String) -> ClipSource { ClipSource(name: name, bundleID: id) }

        store.addFiles([files.brandKit], source: src("Finder", "com.apple.finder"), now: next())
        let address = store.addText("Avenue Mall, Phase 4, Kuwait City", source: src("Maps", "com.apple.Maps"), now: next())
        let email = store.addText("hello@minutechbuilds.com", source: src("Mail", "com.apple.mail"), now: next())
        addImage(DemoArt.png(DemoArt.receipt, size: CGSize(width: 520, height: 470)), store, src("Preview", "com.apple.Preview"), next())
        store.addText("""
            Launch notes: record the demo on Thursday, write the README on Friday, ship v0.1 on Saturday. \
            Keep the video under 40 seconds. Show search, pins, multi-paste and the AI actions. \
            Ask three friends to try it before posting.
            """, source: src("Notes", "com.apple.Notes"), now: next())
        store.addFiles([files.csv], source: src("Finder", "com.apple.finder"), now: next())
        store.addText("git commit -m \"ship it 🚀\"", source: src("Terminal", "com.apple.Terminal"), now: next())
        store.addText("#FF6200", source: src("Figma", "com.figma.Desktop"), now: next())
        addImage(DemoArt.png(DemoArt.slide, size: CGSize(width: 720, height: 420)), store, src("Keynote", "com.apple.iWork.Keynote"), next())
        store.addText("+965 5555 0123", source: src("Messages", "com.apple.MobileSMS"), now: next())
        store.addFiles([files.deck, files.invoice], source: src("Finder", "com.apple.finder"), now: next())
        store.addText("their going to love this, its realy fast and it just works", source: src("Slack", "com.tinyspeck.slackmacgap"), now: next())
        addImage(DemoArt.png(DemoArt.dashboard, size: CGSize(width: 760, height: 440)), store, src("Safari", "com.apple.Safari"), next())
        store.addText("https://github.com/minutechreview", source: src("Safari", "com.apple.Safari"), now: next())
        store.addText("See you at the launch tomorrow! 🎉", source: src("WhatsApp", "net.whatsapp.WhatsApp"), now: next())
        store.addFiles([files.deck], source: src("Finder", "com.apple.finder"), now: next())
        addImage(DemoArt.png(DemoArt.sunset, size: CGSize(width: 640, height: 480)), store, src("Photos", "com.apple.Photos"), next())
        store.addText("Running 5 min late, grabbing coffee ☕️", source: src("Messages", "com.apple.MobileSMS"), now: next())

        for item in [address, email].compactMap({ $0 }) { store.setPinned(true, id: item.id) }
    }

    private static func addImage(_ png: Data?, _ store: ClipStore, _ source: ClipSource, _ date: Date) {
        guard let png else { return }
        store.addImage(png: png, source: source, now: date)
    }

    // MARK: Sample files

    private struct Files { let deck, invoice, csv, brandKit: String }

    private static func makeFiles() -> Files {
        let deck = filesDirectory.appendingPathComponent("Pitch Deck.pdf")
        let invoice = filesDirectory.appendingPathComponent("Invoice 1042.pdf")
        let csv = filesDirectory.appendingPathComponent("budget-2026.csv")
        let kit = filesDirectory.appendingPathComponent("Brand Kit", isDirectory: true)
        writePDF(to: deck, title: "Pocket", lines: ["Your clipboard, in the notch.", "Free · Open source · Private"])
        writePDF(to: invoice, title: "Invoice #1042", lines: ["Website design · 450 KD", "Due: 30 November 2026"])
        try? "month,revenue,costs\nSep,1200,800\nOct,1650,900\nNov,2280,950\n".write(to: csv, atomically: true, encoding: .utf8)
        try? FileManager.default.createDirectory(at: kit, withIntermediateDirectories: true)
        try? "Primary: #FF6200\nBackground: #0A0A0A\nFont: Inter\n".write(
            to: kit.appendingPathComponent("colours.txt"), atomically: true, encoding: .utf8)
        return Files(deck: deck.path, invoice: invoice.path, csv: csv.path, brandKit: kit.path)
    }

    /// A one-page PDF with a big title, so Quick Look and the preview show something real.
    private static func writePDF(to url: URL, title: String, lines: [String]) {
        var box = CGRect(x: 0, y: 0, width: 842, height: 595)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1).setFill()
        box.fill()
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: NSColor.white]
        NSAttributedString(string: title, attributes: titleAttrs).draw(at: CGPoint(x: 60, y: 360))
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .medium),
                                                        .foregroundColor: NSColor(red: 1, green: 0.38, blue: 0, alpha: 1)]
        for (index, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: bodyAttrs).draw(at: CGPoint(x: 62, y: 300 - CGFloat(index) * 44))
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }
}
