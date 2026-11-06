import NotchClipCore
import SwiftUI

/// A large view of one clip: the whole text, the full image, or the file list.
struct PreviewView: View {
    @ObservedObject var model: NotchModel
    let item: ClipItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            sidebar.frame(width: 170)
        }
        .padding(.horizontal, Layout.sidePadding)
        .padding(.bottom, Layout.bottomPadding)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let image = model.fullImage(for: item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(6)
            }
        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 12, design: ClipFlavor.detect(item.text ?? "") == .code ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.filePaths ?? [], id: \.self) { path in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                            Text((path as NSString).lastPathComponent).lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(12)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(details).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            Spacer()
            button("Paste", symbol: "arrow.down.doc.fill", prominent: true) { model.onPick(item, false) }
            if item.kind == .text || item.hasReadableText {
                button(item.kind == .image ? "Paste text" : "Paste as plain text", symbol: "textformat") { model.onPick(item, true) }
            }
            if item.workingText != nil {
                button("AI actions", symbol: "sparkles") { model.showAI(item) }
            }
            button(item.pinned ? "Unpin" : "Pin", symbol: item.pinned ? "pin.slash" : "pin") { model.onTogglePin(item) }
        }
        .foregroundStyle(.white)
    }

    private var details: String {
        var lines = [RelativeTime.short(from: item.date) == "now" ? "Copied just now" : "Copied \(RelativeTime.short(from: item.date)) ago"]
        if let app = item.source?.name { lines.append("From \(app)") }
        switch item.kind {
        case .text: lines.append("\((item.text ?? "").count) characters")
        case .image: if let w = item.pixelWidth, let h = item.pixelHeight { lines.append("\(w) × \(h) pixels") }
        case .file: lines.append("\(item.filePaths?.count ?? 0) file(s)")
        }
        return lines.joined(separator: "\n")
    }

    private func button(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? Color.notchAccent : Color.white.opacity(0.1)))
                .foregroundStyle(prominent ? .black : .white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
