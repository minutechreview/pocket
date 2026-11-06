import NotchClipCore
import SwiftUI

extension Color {
    /// Rayan's brand orange.
    static let notchAccent = Color(red: 1.0, green: 0.384, blue: 0.0)
}

/// The black shape that grows out of the notch.
struct NotchView: View {
    @ObservedObject var model: NotchModel

    private var shapeSize: CGSize { model.isOpen ? model.openSize : model.notchSize }
    private var radius: CGFloat { model.isOpen ? Layout.openRadius : Layout.closedRadius }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
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
        .clipShape(shape)
        .shadow(color: .black.opacity(model.isOpen ? 0.5 : 0), radius: 16, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(spacing: 6) {
            header
            if model.items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(width: model.openSize.width, height: model.openSize.height, alignment: .top)
        .overlay(alignment: .bottom) { toast }
    }

    /// Sits on either side of the physical notch.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(Color.notchAccent)
            Text("Clipboard")
                .fontWeight(.semibold)
            Spacer()
            Text(model.keyboardMode ? "← → to choose · ⏎ to paste" : "Click to paste · ⌃⇧C")
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .frame(height: model.headerHeight)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(Layout.cardWidth), spacing: Layout.gap), count: Layout.columns),
                    spacing: Layout.gap
                ) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipCard(
                            item: item,
                            index: index,
                            isSelected: model.keyboardMode && index == model.selection,
                            thumbnail: item.kind == .image ? model.thumbnail(for: item) : nil,
                            appIcon: model.appIcon(for: item)
                        )
                        .id(item.id)
                        .onTapGesture { model.onPick(item) }
                        .contextMenu {
                            Button("Paste") { model.onPick(item) }
                            Button("Delete", role: .destructive) { model.onDelete(item) }
                        }
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28))
            Text("Copy some text or take a screenshot.\nIt shows up here.")
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
