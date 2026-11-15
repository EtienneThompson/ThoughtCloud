import Foundation

/// What the capture field currently means. Pure value; the UI shows it live.
public struct CaptureDraft: Hashable, Sendable {
    public var title: String
    public var body: String
    public var suggestedKind: ItemKind
    /// Tags as typed (without `#`), unique case-insensitively, in order.
    public var hashtags: [String]
    /// A tag still being typed at the very end of the text (for autocomplete).
    public var hashtagInProgress: String?
    public var detectedDate: DetectedDate?

    public var isEmpty: Bool { title.isEmpty && body.isEmpty }
}

/// Turns one free-text field into a draft: first line → title, rest → body,
/// `#tags` → categories, a date in the title → due / remember-until, plus a
/// best guess at the kind. Never asks questions; the user can override.
public struct CaptureParser: Sendable {
    let dateDetector: any DateDetecting

    public init(dateDetector: any DateDetecting) {
        self.dateDetector = dateDetector
    }

    public func parse(_ raw: String) -> CaptureDraft {
        let inProgress = Self.hashtagInProgress(in: raw)
        let (withoutTags, tags) = Self.extractHashtags(from: raw)
        let normalized = withoutTags.replacingOccurrences(of: "\u{2019}", with: "'")

        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { Self.collapseSpaces(String($0)) }
        let firstIndex = lines.firstIndex { !$0.isEmpty }
        var title = firstIndex.map { lines[$0] } ?? ""
        let body = firstIndex.map { lines[($0 + 1)...].joined(separator: "\n") }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var explicitKind: ItemKind?
        if let (kind, rest) = Self.explicitPrefix(title) {
            explicitKind = kind
            title = rest
        }

        let date = title.isEmpty ? nil : dateDetector.detectDate(in: title)
        let kind = explicitKind ?? Self.guessKind(title: title, body: body, hasDate: date != nil, hasTime: date?.hasTime ?? false)

        return CaptureDraft(
            title: title,
            body: body,
            suggestedKind: kind,
            hashtags: tags,
            hashtagInProgress: inProgress,
            detectedDate: date
        )
    }

    // MARK: - Kind

    static let todoVerbs: Set<String> = [
        "apply", "ask", "book", "bring", "buy", "call", "cancel", "check", "clean", "contact",
        "draft", "drop", "email", "file", "finish", "fix", "follow", "get", "go", "install",
        "mail", "make", "message", "order", "pay", "pick", "plan", "prep", "prepare", "print",
        "register", "renew", "reply", "research", "return", "review", "schedule", "send", "set",
        "ship", "sign", "submit", "take", "text", "update", "visit", "wash", "water", "write",
    ]

    static func guessKind(title: String, body: String, hasDate: Bool, hasTime: Bool = false) -> ItemKind {
        let lower = title.lowercased()
        for prefix in ["remember to ", "don't forget to ", "dont forget to "] where lower.hasPrefix(prefix) {
            return .todo
        }
        for prefix in ["remember that ", "don't forget that ", "dont forget that ", "remember "] where lower.hasPrefix(prefix) {
            return .review
        }
        let firstWord = lower.split(separator: " ").first.map { $0.trimmingCharacters(in: .punctuationCharacters) } ?? ""
        if todoVerbs.contains(firstWord) { return .todo }
        if hasTime { return .event }
        if hasDate { return .review }
        let bodyLines = BodyFormatter.blocks(from: body)
        if !bodyLines.isEmpty && bodyLines.contains(where: { if case .labeled = $0 { true } else { false } }) {
            return .review
        }
        return .thought
    }

    static func explicitPrefix(_ title: String) -> (ItemKind, String)? {
        let prefixes: [(String, ItemKind)] = [
            ("todo", .todo), ("t", .todo),
            ("thought", .thought), ("idea", .thought),
            ("review", .review), ("remember", .review), ("r", .review),
            ("event", .event), ("e", .event),
        ]
        for (word, kind) in prefixes {
            guard title.count > word.count, title.lowercased().hasPrefix(word) else { continue }
            let rest = title.dropFirst(word.count)
            let afterSpaces = rest.drop(while: { $0 == " " })
            guard afterSpaces.first == ":" else { continue }
            return (kind, afterSpaces.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: - Hashtags

    private static let hashtagRegex = try! NSRegularExpression(pattern: #"(?<![\w#])#([A-Za-z][\w-]*)"#)
    private static let inProgressRegex = try! NSRegularExpression(pattern: #"(?:^|\s)#([\w-]*)$"#)

    static func extractHashtags(from text: String) -> (String, [String]) {
        let ns = text as NSString
        var tags: [String] = []
        var seen = Set<String>()
        for match in hashtagRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1))
            if seen.insert(tag.lowercased()).inserted { tags.append(tag) }
        }
        let stripped = hashtagRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return (stripped, tags)
    }

    static func hashtagInProgress(in text: String) -> String? {
        let ns = text as NSString
        guard let match = inProgressRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    static func collapseSpaces(_ line: String) -> String {
        line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Matches typed `#tags` to category names, ignoring case, spaces and dashes.
public enum CategoryMatcher {
    public static func key(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func displayName(fromHashtag tag: String) -> String {
        tag.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    public static func find(_ tag: String, in categories: [ItemCategory]) -> ItemCategory? {
        let k = key(tag)
        return categories.first { key($0.name) == k }
    }
}
