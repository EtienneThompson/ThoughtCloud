import Foundation

/// Light, content-agnostic formatting for item bodies. No templates: any text
/// works, and a few line shapes get nicer presentation.
public enum BodyBlock: Hashable, Sendable {
    case text(String)
    case bullet(String)
    case numbered(String, String)
    case labeled(String, String)
}

public enum BodyFormatter {
    static let maxLabelLength = 24
    static let maxLabelWords = 4

    public static func blocks(from body: String) -> [BodyBlock] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(block(for:))
    }

    static func block(for line: String) -> BodyBlock {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return .bullet(String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        if let numbered = numbered(line) { return numbered }
        if let (label, value) = labelValue(line) { return .labeled(label, value) }
        return .text(line)
    }

    private static func numbered(_ line: String) -> BodyBlock? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let marker = rest.first, marker == "." || marker == ")" else { return nil }
        let afterMarker = rest.dropFirst()
        guard afterMarker.first == " " else { return nil }
        return .numbered(String(digits), afterMarker.trimmingCharacters(in: .whitespaces))
    }

    /// Splits `label: value` lines, where the label is short. The colon must be
    /// followed by a space so times (3:40) and URLs (https://) never match.
    public static func labelValue(_ line: String) -> (String, String)? {
        guard let range = line.range(of: ": ") else { return nil }
        let label = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !value.isEmpty,
              label.count <= maxLabelLength,
              label.split(separator: " ").count <= maxLabelWords
        else { return nil }
        return (label, value)
    }
}
