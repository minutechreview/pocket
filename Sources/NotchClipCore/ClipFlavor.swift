import Foundation

/// What a text clip looks like, so its card can show a smart preview.
public enum ClipFlavor: Equatable, Sendable {
    case plain
    case link(host: String)
    case email
    case phone
    /// A colour such as #FF6200, with its RGB values 0…1.
    case color(red: Double, green: Double, blue: Double)
    case code

    public static func detect(_ text: String) -> ClipFlavor {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plain }
        let singleLine = !trimmed.contains("\n")

        if singleLine, let color = hexColor(trimmed) { return color }
        if singleLine, !trimmed.contains(" "), let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host() {
            return .link(host: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
        }
        if singleLine, trimmed.wholeMatch(of: #/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/#) != nil {
            return .email
        }
        if singleLine, trimmed.wholeMatch(of: #/\+?[0-9][0-9 ()\-]{6,18}[0-9]/#) != nil {
            return .phone
        }
        return looksLikeCode(trimmed) ? .code : .plain
    }

    private static func hexColor(_ text: String) -> ClipFlavor? {
        guard let match = text.wholeMatch(of: #/#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})/#) else { return nil }
        // A bare 3/6-digit number like "123456" is more likely a number than a colour.
        guard text.hasPrefix("#") || match.1.contains(where: \.isLetter) else { return nil }
        var hex = String(match.1)
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(hex, radix: 16) else { return nil }
        return .color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Rough check: several code-only symbols, or typical keywords at line starts.
    private static func looksLikeCode(_ text: String) -> Bool {
        let symbols = text.filter { "{};=<>()[]$&|".contains($0) }.count
        let keywords = ["func ", "function ", "const ", "let ", "var ", "import ", "def ", "class ",
                        "return ", "if (", "npm ", "git ", "cd ", "SELECT ", "<div", "#include", "pip "]
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let keywordLines = lines.filter { line in keywords.contains { line.hasPrefix($0) } }.count
        return keywordLines > 0 || Double(symbols) / Double(max(text.count, 1)) > 0.06
    }
}
