import AppKit
import NotchClipCore
import ServiceManagement
import SwiftUI

/// The Settings window: General, Privacy and AI tabs.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onClearHistory: () -> Void

    var body: some View {
        TabView {
            GeneralTab(settings: settings, onClearHistory: onClearHistory)
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacyTab(settings: settings)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            AITab(settings: settings)
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 520, height: 440)
        .tint(.notchAccent)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    let onClearHistory: () -> Void
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Open clipboard") { ShortcutRecorder(shortcut: $settings.value.openShortcut) }
                LabeledContent("Paste next from stack") { ShortcutRecorder(shortcut: $settings.value.stackShortcut) }
            }
            Section("History") {
                Picker("Keep", selection: $settings.value.historyLimit) {
                    ForEach(AppSettings.historyChoices, id: \.self) { Text("Last \($0) clips").tag($0) }
                }
                Picker("Delete clips older than", selection: $settings.value.autoDeleteDays) {
                    ForEach(AppSettings.autoDeleteChoices, id: \.self) { days in
                        Text(days == 0 ? "Never" : days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                Toggle("Keep formatting when pasting (bold, links, fonts)", isOn: $settings.value.keepFormatting)
                Text("Pinned clips are never deleted automatically. ⌥-click a clip to paste it as plain text.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear History…", role: .destructive, action: onClearHistory)
            }
            Section("Startup") {
                Toggle("Open Pocket at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in setLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct PrivacyTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(settings.value.ignoredApps, id: \.self) { app in
                    HStack {
                        appIcon(app.bundleID)
                        Text(app.name)
                        Spacer()
                        Button(role: .destructive) {
                            settings.value.ignoredApps.removeAll { $0 == app }
                        } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…", action: addApp)
            } header: {
                Text("Never save copies from these apps")
            } footer: {
                Text("Passwords copied from password managers are always skipped. Everything Pocket saves stays on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func appIcon(_ bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "app").frame(width: 18, height: 18)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { url -> IgnoredApp? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return IgnoredApp(name: name, bundleID: id)
        }
        settings.value.ignoredApps = settings.value.ignoredApps + added.filter { !settings.value.ignoredApps.contains($0) }
    }
}

/// Click, then press the new key combination.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : shortcut.label) {
            recording ? stop() : start()
        }
        .font(.system(.body, design: .rounded).weight(.semibold))
        .frame(minWidth: 110)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            if let new = Shortcut(event: event) {
                shortcut = new
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
