import NotchClipCore
import SwiftUI

/// One copied item: a text snippet or an image thumbnail, with where and when it came from.
struct ClipCard: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let thumbnail: NSImage?
    let appIcon: NSImage?

    @State private var isHovering = false

    private var isHighlighted: Bool { isHovering || isSelected }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
                .frame(width: Layout.cardWidth - 14, height: Layout.cardHeight - 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            footer
        }
        .padding(7)
        .frame(width: Layout.cardWidth, height: Layout.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.14 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isHighlighted ? Color.notchAccent : .clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isHovering ? 1.03 : 1)
        .animation(.snappy(duration: 0.15), value: isHighlighted)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white.opacity(0.05))
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Layout.cardWidth - 14, height: Layout.cardHeight - 38)
                    .clipped()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.05))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            Text(caption)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 2)
            if index < 10 {
                Text(index == 9 ? "0" : "\(index + 1)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isHighlighted ? .black : .white.opacity(0.6))
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(isHighlighted ? Color.notchAccent : Color.white.opacity(0.12)))
            }
        }
        .font(.system(size: 10))
    }

    private var caption: String {
        [RelativeTime.short(from: item.date), item.source?.name].compactMap { $0 }.joined(separator: " · ")
    }

    private var tooltip: String {
        guard item.kind == .image else { return String((item.text ?? "").prefix(300)) }
        guard let width = item.pixelWidth, let height = item.pixelHeight else { return "Image" }
        return "Image · \(width)×\(height)"
    }
}
