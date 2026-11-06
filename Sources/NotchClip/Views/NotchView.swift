import AppKit
import NotchClipCore
import SwiftUI

extension Color {
    /// Rayan's brand orange.
    static let notchAccent = Color(red: 1.0, green: 0.384, blue: 0.0)
}

/// The black shape that grows out of the notch. Shows the clips, a big preview, or the AI panel.
struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var settings: SettingsStore
    @FocusState private var searchFocused: Bool

    private var shapeSize: CGSize { model.isOpen ? model.openSize : model.notchSize }
    private var radius: CGFloat { model.isOpen ? Layout.openRadius : Layout.closedRadius }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
    }
    private var aiBusy: Bool {
        switch model.aiRun?.status {
        case .thinking, .writing: return true
        default: return false
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if model.isOpen {
                content
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: shapeSize.width, height: shapeSize.height, alignment: .top)
        .background(Color.black.opacity(model.hasNotch || model.isOpen ? 1 : 0.001))
        .overlay { if aiBusy && model.isOpen { AIGlowBorder(radius: radius).transition(.opacity) } }
        .clipShape(shape)
        .shadow(color: .black.opacity(model.isOpen ? 0.5 : 0), radius: 16, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.3), value: aiBusy)
        .onChange(of: model.keyboardMode) { _, keyboard in searchFocused = keyboard && model.mode == .clips }
    }

    private var content: some View {
        VStack(spacing: 6) {
            header
            switch model.mode {
            case .clips:
                if model.items.isEmpty { emptyState(searching: !model.query.isEmpty) } else { grid }
            case .preview(let item):
                PreviewView(model: model, item: item)
            case .ai(let item):
                AIPanelView(model: model, item: item, languages: settings.value.translateLanguages,
                            isChatGPT: settings.value.aiProvider == .chatGPT)
            }
        }
        .frame(width: model.openSize.width, height: model.openSize.height, alignment: .top)
        .overlay(alignment: .bottom) { toast }
    }

    // MARK: Header (sits on either side of the physical notch)

    private var header: some View {
        HStack(spacing: 8) {
            switch model.mode {
            case .clips:
                if model.stack.isEmpty { title("Clipboard", symbol: "doc.on.clipboard.fill") } else { stackBar }
                Spacer()
                searchField
                iconButton("gearshape", help: "Settings") { model.onOpenSettings() }
            case .preview:
                backButton
                title("Preview", symbol: "eye.fill")
                Spacer()
            case .ai:
                backButton
                title("AI", symbol: "sparkles")
                Spacer()
                Text(model.aiProviderName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .frame(height: model.headerHeight)
    }

    private func title(_ text: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Color.notchAccent)
            Text(text).fontWeight(.semibold)
        }
    }

    private var backButton: some View {
        Button { model.backToClips() } label: {
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help("Back (Esc)")
    }

    /// Shown when clips are queued with ⌘-click.
    private var stackBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.notchAccent)
            Text("Stack · \(model.stack.count)").fontWeight(.semibold)
            Button("Paste all") { model.onPasteStack() }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).frame(height: 20)
                .background(Capsule().fill(Color.notchAccent)).foregroundStyle(.black)
            Text("\(settings.value.stackShortcut.label) pastes next").foregroundStyle(.white.opacity(0.45))
            iconButton("xmark", help: "Clear stack") { model.clearStack() }
        }
        .font(.system(size: 11))
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(.white.opacity(0.6)).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
            TextField("Search clips & screenshots", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: model.stack.isEmpty ? 230 : 180, height: 24)
        .background(Capsule().fill(Color.white.opacity(searchFocused ? 0.16 : 0.09)))
    }

    // MARK: Clips

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(Layout.cardWidth), spacing: Layout.gap), count: Layout.columns),
                    spacing: Layout.gap
                ) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        card(item, index: index)
                    }
                }
                .padding(.horizontal, Layout.sidePadding)
                .padding(.bottom, Layout.bottomPadding)
            }
            .onChange(of: model.selection) { _, newValue in
                guard model.items.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(model.items[newValue].id) }
            }
        }
    }

    private func card(_ item: ClipItem, index: Int) -> some View {
        ClipCard(
            item: item,
            index: index,
            isSelected: model.keyboardMode && index == model.selection,
            stackPosition: model.stackPosition(of: item),
            thumbnail: item.kind == .image ? model.thumbnail(for: item) : nil,
            appIcon: model.appIcon(for: item),
            onAI: { model.showAI(item) }
        )
        .id(item.id)
        .onTapGesture { tapped(item) }
        .onDrag { DragPayload.provider(for: item, model: model) }
        .contextMenu { menu(for: item) }
    }

    /// Click pastes; ⌥-click pastes plain text; ⌘-click adds to the paste stack.
    private func tapped(_ item: ClipItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            model.toggleStack(item)
        } else {
            model.onPick(item, flags.contains(.option))
        }
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("Paste") { model.onPick(item, false) }
        if item.kind == .text { Button("Paste as Plain Text") { model.onPick(item, true) } }
        if item.hasReadableText { Button("Paste Text from Image") { model.onPick(item, true) } }
        Button("Preview") { model.showPreview(item) }
        if item.workingText != nil {
            Menu("AI") {
                ForEach(AIAction.quick, id: \.self) { action in
                    Button(action.title) { model.showAI(item); model.onRunAI(item, action) }
                }
                Menu("Translate") {
                    ForEach(settings.value.translateLanguages, id: \.self) { language in
                        Button(language) { model.showAI(item); model.onRunAI(item, .translate(language)) }
                    }
                }
                Button("Ask…") { model.showAI(item) }
            }
        }
        Button(model.stackPosition(of: item) == nil ? "Add to Paste Stack" : "Remove from Paste Stack") { model.toggleStack(item) }
        Button(item.pinned ? "Unpin" : "Pin") { model.onTogglePin(item) }
        Divider()
        Button("Delete", role: .destructive) { model.onDelete(item) }
    }

    private func emptyState(searching: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 28))
            Text(searching ? "Nothing matches “\(model.query)”" : "Copy some text or take a screenshot.\nIt shows up here.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12))
        }
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var toast: some View {
        if let text = model.toast {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.notchAccent))
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// What a card carries when dragged out of the notch into another app.
@MainActor
enum DragPayload {
    static func provider(for item: ClipItem, model: NotchModel) -> NSItemProvider {
        switch item.kind {
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .image:
            return model.imageFileURL(for: item).flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider()
        case .file:
            return (item.filePaths?.first).flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
        }
    }
}
