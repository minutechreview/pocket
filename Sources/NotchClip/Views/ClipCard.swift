import AppKit
import NotchClipCore
import SwiftUI

/// One copied item with a smart preview (link, colour, code, file, image) and where/when it came from.
struct ClipCard: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    /// Position in the paste stack (1-based), or nil when not stacked.
    let stackPosition: Int?
    let thumbnail: NSImage?
    let appIcon: NSImage?
    let onAI: () -> Void

    @State private var isHovering = false

    private var isHighlighted: Bool { isHovering || isSelected || stackPosition != nil }
    private var previewSize: CGSize { CGSize(width: Layout.cardWidth - 14, height: Layout.cardHeight - 38) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardPreview(item: item, thumbnail: thumbnail, size: previewSize)
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(alignment: .topTrailing) { badges }
                .overlay(alignment: .topLeading) { aiButton }
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

    /// A small sparkle that opens the AI actions for this clip (shown on hover).
    @ViewBuilder
    private var aiButton: some View {
        if isHovering, item.workingText != nil {
            Button(action: onAI) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.notchAccent))
            }
            .buttonStyle(.plain)
            .padding(5)
            .help("AI actions (⌘J)")
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Paste-stack number, pin marker, and a TEXT chip on screenshots whose text can be pasted.
    private var badges: some View {
        HStack(spacing: 4) {
            if item.hasReadableText {
                Text("TEXT")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .foregroundStyle(.white)
            }
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.notchAccent))
            }
            if let stackPosition {
                Text("\(stackPosition)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(Color.white))
                    .transition(.scale)
            }
        }
        .padding(5)
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
        switch item.kind {
        case .text: return String((item.text ?? "").prefix(300))
        case .file: return (item.filePaths ?? []).joined(separator: "\n")
        case .image:
            guard let width = item.pixelWidth, let height = item.pixelHeight else { return "Image" }
            return "Image · \(width)×\(height)"
        }
    }
}

/// The top part of a card: what the clip actually is.
struct CardPreview: View {
    let item: ClipItem
    let thumbnail: NSImage?
    let size: CGSize

    var body: some View {
        switch item.kind {
        case .image: imagePreview
        case .file: filePreview
        case .text: textPreview(ClipFlavor.detect(item.text ?? ""))
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            placeholder("photo")
        }
    }

    private var filePreview: some View {
        let paths = item.filePaths ?? []
        return VStack(spacing: 4) {
            if let first = paths.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                    .resizable()
                    .frame(width: 38, height: 38)
            }
            Text(paths.count > 1 ? "\(paths.count) files" : item.fileNames.first ?? "File")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.05))
    }

    @ViewBuilder
    private func textPreview(_ flavor: ClipFlavor) -> some View {
        switch flavor {
        case .color(let red, let green, let blue):
            ZStack(alignment: .bottomLeading) {
                Color(red: red, green: green, blue: blue)
                Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        case .link(let host):
            labeled(symbol: "link", title: host, body: item.text ?? "", monospaced: false)
        case .email:
            labeled(symbol: "envelope.fill", title: "Email", body: item.text ?? "", monospaced: false)
        case .phone:
            labeled(symbol: "phone.fill", title: "Phone", body: item.text ?? "", monospaced: false)
        case .code:
            plainText(monospaced: true)
        case .plain:
            plainText(monospaced: false)
        }
    }

    private func labeled(symbol: String, title: String, body: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(Color.notchAccent)
                Text(title).fontWeight(.semibold).lineLimit(1)
            }
            .font(.system(size: 12))
            Text(body.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(3)
        }
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05))
    }

    private func plainText(monospaced: Bool) -> some View {
        Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            .font(.system(size: monospaced ? 10 : 11, design: monospaced ? .monospaced : .default))
            .foregroundStyle(monospaced ? Color(red: 0.6, green: 0.9, blue: 0.7) : .white.opacity(0.92))
            .lineLimit(5)
            .multilineTextAlignment(.leading)
            .padding(8)
            .padding(.trailing, item.pinned ? 14 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(monospaced ? Color.white.opacity(0.03) : Color.white.opacity(0.05))
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.05))
    }
}
