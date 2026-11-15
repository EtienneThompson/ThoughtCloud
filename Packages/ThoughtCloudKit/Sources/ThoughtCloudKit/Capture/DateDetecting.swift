import Foundation

public struct DetectedDate: Hashable, Sendable {
    public var date: Date
    /// False for phrases like "Monday" or "Jan 10" (the system reports noon for those).
    public var hasTime: Bool
    public var matchedText: String

    public init(date: Date, hasTime: Bool, matchedText: String) {
        self.date = date
        self.hasTime = hasTime
        self.matchedText = matchedText
    }
}

/// Seam over natural-language date parsing so the parser can be tested with fixed dates.
public protocol DateDetecting: Sendable {
    func detectDate(in text: String) -> DetectedDate?
}

/// `NSDataDetector`-backed detector. Relative phrases resolve against the real current time.
public final class SystemDateDetector: DateDetecting, @unchecked Sendable {
    // NSRegularExpression subclasses are documented as thread-safe for matching.
    private let detector: NSDataDetector?
    private let timePattern: NSRegularExpression?

    public init() {
        detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        timePattern = try? NSRegularExpression(
            pattern: #"\d{1,2}:\d{2}|\d\s*(am|pm|a\.m\.|p\.m\.)\b|\bat\s+\d{1,2}\b|\bnoon\b|\bmidnight\b|\btonight\b|\bthis (morning|afternoon|evening)\b"#,
            options: [.caseInsensitive]
        )
    }

    public func detectDate(in text: String) -> DetectedDate? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range),
              let date = match.date,
              let matchRange = Range(match.range, in: text)
        else { return nil }
        let matched = String(text[matchRange])
        let hasTime = timePattern?.firstMatch(in: matched, range: NSRange(matched.startIndex..., in: matched)) != nil
        return DetectedDate(date: date, hasTime: hasTime, matchedText: matched)
    }
}
