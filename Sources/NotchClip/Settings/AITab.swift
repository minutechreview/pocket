import AppKit
import NotchClipCore
import SwiftUI

/// Settings → AI: pick who answers (Apple on-device, ChatGPT plan, or an API key) and sign in.
struct AITab: View {
    @ObservedObject var settings: SettingsStore
    @State private var chatGPT = ChatGPTAuth.State.signedOut
    @State private var busy = false
    @State private var error: String?
    @State private var models: [AIModel] = []
    @State private var apiKey = Keychain.apiKey ?? ""
    @State private var showWelcome = false
    @State private var languages = ""

    var body: some View {
        Form {
            Section("Who answers") {
                Picker("AI", selection: $settings.value.aiProvider) {
                    ForEach(AIProviderKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.value.aiProvider) { _, _ in
                    settings.value.aiModel = nil
                    Task { await loadModels() }
                }
            }
            switch settings.value.aiProvider {
            case .apple: appleSection
            case .chatGPT: chatGPTSection
            case .openAIKey: apiKeySection
            }
            Section("Translate to") {
                TextField("Languages, separated by commas", text: $languages)
                    .onSubmit(saveLanguages)
                    .onChange(of: languages) { _, _ in saveLanguages() }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .task {
            languages = settings.value.translateLanguages.joined(separator: ", ")
            chatGPT = await ChatGPTAuth.shared.state
            await loadModels()
        }
        .alert("You're using your ChatGPT plan", isPresented: $showWelcome) {
            Button("Got it") { settings.value.hasSeenChatGPTWelcome = true }
        } message: {
            Text("NotchClip's AI actions will use the usage included in your ChatGPT plan. You can review and limit it any time in ChatGPT settings → Usage.")
        }
    }

    private var appleSection: some View {
        Section {
            if let reason = AppleProvider.unavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                Label("Ready. Runs privately on this Mac, free and offline.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text("Apple's model works with text (including text read from screenshots). For questions about the picture itself, use ChatGPT.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chatGPTSection: some View {
        Section {
            switch chatGPT {
            case .signedOut:
                Text("Use your ChatGPT plan in NotchClip. No API key needed.")
                Button(action: signIn) {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small) } else { Image(systemName: "bubble.left.and.bubble.right.fill") }
                        Text(busy ? "Waiting for your browser…" : "Continue with ChatGPT").fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.black))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            case .connected(let email, let planUsage):
                LabeledContent("Account") { Text(email ?? "Connected") }
                if planUsage {
                    HStack {
                        Label("Using ChatGPT plan", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Manage usage") { NSWorkspace.shared.open(ChatGPTAuth.usageURL) }
                    }
                } else {
                    Label("ChatGPT plan use is off.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Turn on ChatGPT plan use", action: signIn).disabled(busy)
                }
                modelPicker
                Button("Sign out", role: .destructive, action: signOut)
            }
        } footer: {
            Text("Works with ChatGPT Plus and Pro. Your ChatGPT chats are never accessed. Sign-in details are saved only on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureField("sk-…", text: $apiKey)
            HStack {
                Button("Save key") {
                    Keychain.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    Task { await loadModels() }
                }
                Button("Remove", role: .destructive) {
                    apiKey = ""
                    Keychain.setAPIKey(nil)
                    models = []
                }
            }
            modelPicker
        } footer: {
            Text("Stored in your Mac's Keychain. Requests are billed to your OpenAI account.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        if !models.isEmpty {
            Picker("Model", selection: Binding(
                get: { settings.value.aiModel ?? models.first?.slug ?? "" },
                set: { settings.value.aiModel = $0 }
            )) {
                ForEach(models) { Text($0.displayName).tag($0.slug) }
            }
        }
    }

    // MARK: Actions

    private func signIn() {
        busy = true
        error = nil
        Task {
            do {
                chatGPT = try await ChatGPTAuth.shared.signIn { url in
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                }
                NSApp.activate()
                if case .connected(_, true) = chatGPT, !settings.value.hasSeenChatGPTWelcome { showWelcome = true }
                await loadModels()
            } catch {
                self.error = AIService.message(for: error)
            }
            busy = false
        }
    }

    private func signOut() {
        Task {
            let revoked = await ChatGPTAuth.shared.signOut()
            chatGPT = await ChatGPTAuth.shared.state
            models = []
            if !revoked {
                error = "Signed out on this Mac. OpenAI didn't confirm, so you can also disconnect NotchClip in ChatGPT settings."
            }
        }
    }

    private func loadModels() async {
        do {
            switch settings.value.aiProvider {
            case .apple:
                models = []
            case .chatGPT:
                guard case .connected(_, true) = chatGPT else { models = []; return }
                let token = try await ChatGPTAuth.shared.accessToken()
                models = try await ResponsesClient.listModels(token: token, planUsage: true)
            case .openAIKey:
                guard let key = Keychain.apiKey, !key.isEmpty else { models = []; return }
                models = try await ResponsesClient.listModels(token: key, planUsage: false)
            }
            error = nil
        } catch {
            models = []
            self.error = AIService.message(for: error)
        }
    }

    private func saveLanguages() {
        let list = languages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !list.isEmpty { settings.value.translateLanguages = list }
    }
}
