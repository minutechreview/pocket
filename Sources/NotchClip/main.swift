import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if Snapshot.runIfRequested() { exit(0) }
    if let flag = CommandLine.arguments.firstIndex(of: "--ai-test"), CommandLine.arguments.count > flag + 1 {
        // Developer check: runs one AI rewrite through the on-device model and prints it.
        let request = AIRequest(instructions: AIAction.fixGrammar.instructions, text: CommandLine.arguments[flag + 1], imagePNG: nil)
        Task {
            do {
                var last = ""
                for try await text in AppleProvider().stream(request) { last = text }
                print(AIService.clean(last))
            } catch {
                print("ERROR:", AIService.message(for: error))
            }
            exit(0)
        }
        RunLoop.main.run()
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
