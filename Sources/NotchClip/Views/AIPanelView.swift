import NotchClipCore
import SwiftUI

/// The AI view inside the notch: the clip and actions on the left, the answer on the right.
struct AIPanelView: View {
    @ObservedObject var model: NotchModel
    let item: ClipItem
    let languages: [String]
    let isChatGPT: Bool

    @State private var question = ""
    @FocusState private var askFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            actions
                .frame(width: 232)
            result
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        }
        .padding(.horizontal, Layout.sidePadding)
        .padding(.bottom, Layout.bottomPadding)
        .onAppear { askFocused = true }
    }

    // MARK: Left: clip + actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardPreview(item: item, thumbnail: model.thumbnail(for: item), size: CGSize(width: 232, height: 52))
                .frame(width: 232, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(AIAction.quick, id: \.self) { action in
                    chip(action.title, symbol: action.symbol) { run(action) }
                }
            }
            Menu {
                ForEach(languages, id: \.self) { language in
                    Button(language) { run(.translate(language)) }
                }
            } label: {
                Label("Translate…", systemImage: "globe").font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.white)
            askField
        }
    }

    private var askField: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left").foregroundStyle(.white.opacity(0.5))
            TextField(item.kind == .image ? "Ask about this screenshot…" : "Ask anything about this clip…", text: $question)
                .textFieldStyle(.plain)
                .focused($askFocused)
                .onSubmit {
                    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    run(.ask(trimmed))
                }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(askFocused ? 0.16 : 0.09)))
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.09)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func run(_ action: AIAction) {
        model.onRunAI(item, action)
    }

    // MARK: Right: the answer

    @ViewBuilder
    private var result: some View {
        if let run = model.aiRun {
            switch run.status {
            case .thinking:
                ThinkingView(providerName: model.aiProviderName)
            case .writing(let text):
                answer(text, run: run, finished: false)
            case .done(let text):
                answer(text, run: run, finished: true)
            case .failed(let message):
                failure(message, run: run)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(Color.notchAccent)
                Text("Pick an action, or ask anything about this clip.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                Text(model.aiProviderName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private func answer(_ text: String, run: AIRun, finished: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: run.action.symbol).foregroundStyle(Color.notchAccent)
                Text(run.action.title).fontWeight(.semibold).lineLimit(1)
                Spacer()
                usageBadge
            }
            .font(.system(size: 11))
            ScrollView {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(text)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !finished { WritingCaret() }
                }
            }
            if finished {
                HStack(spacing: 8) {
                    actionButton("Paste", symbol: "arrow.down.doc.fill", prominent: true) { model.onUseAIResult(text, true) }
                    actionButton("Copy", symbol: "doc.on.doc", prominent: false) { model.onUseAIResult(text, false) }
                    actionButton("Again", symbol: "arrow.clockwise", prominent: false) { model.onRunAI(run.item, run.action) }
                    Spacer()
                    Text("⌘⏎ paste").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .animation(.snappy(duration: 0.2), value: finished)
    }

    private func failure(_ message: String, run: AIRun) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
            HStack {
                if isChatGPT, message == AIError.usageLimit.localizedDescription {
                    actionButton("Manage usage", symbol: "chart.bar", prominent: true) { NSWorkspace.shared.open(ChatGPTAuth.usageURL) }
                }
                actionButton("Try again", symbol: "arrow.clockwise", prominent: false) { model.onRunAI(run.item, run.action) }
                actionButton("Settings", symbol: "gearshape", prominent: false) { model.onOpenSettings() }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var usageBadge: some View {
        if isChatGPT {
            Button { NSWorkspace.shared.open(ChatGPTAuth.usageURL) } label: {
                Text("Manage usage").font(.system(size: 10)).underline().foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(prominent ? Color.notchAccent : Color.white.opacity(0.12)))
                .foregroundStyle(prominent ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}
