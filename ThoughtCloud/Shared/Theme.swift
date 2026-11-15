import SwiftUI
import ThoughtCloudKit

nonisolated enum Theme {
    static let background = Color(hex: "#0B0B0F")
    static let card = Color(hex: "#1A1A21")
    static let card2 = Color(hex: "#23232C")
    static let line = Color(hex: "#2C2C36")
    static let dim = Color(hex: "#8E8E99")
    static let text = Color(hex: "#F4F4F7")
    static let accent = Color(hex: "#8E8BFF")
    static let danger = Color(hex: "#FF7A6B")
    static let success = Color(hex: "#34C759")
    static let captureGradient = LinearGradient(colors: [ItemKind.todo.color, ItemKind.review.color], startPoint: .topLeading, endPoint: .bottomTrailing)
}

nonisolated extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

nonisolated extension ItemKind {
    var color: Color {
        switch self {
        case .todo: Color(hex: "#4FA3FF")
        case .thought: Color(hex: "#FFB547")
        case .review: Color(hex: "#B07CFF")
        case .event: Color(hex: "#FF6FAE")
        }
    }

    var label: String {
        switch self {
        case .todo: "Todo"
        case .thought: "Thought"
        case .review: "Review"
        case .event: "Event"
        }
    }

    var plural: String {
        switch self {
        case .todo: "Todos"
        case .thought: "Thoughts"
        case .review: "Review"
        case .event: "Events"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "checkmark.circle"
        case .thought: "lightbulb"
        case .review: "arrow.triangle.2.circlepath"
        case .event: "calendar"
        }
    }
}

nonisolated extension CategoryStyle {
    var colors: [Color] { colorHexes.map(Color.init(hex:)) }
    var primary: Color { Color(hex: primaryHex) }

    /// Fill for stripes and edges: solid, two-colour gradient, or white.
    var gradient: LinearGradient {
        let c = colors
        return LinearGradient(colors: c.count == 1 ? [c[0], c[0]] : c, startPoint: .leading, endPoint: .trailing)
    }
}

extension View {
    func cardBackground(_ color: Color = Theme.card, radius: CGFloat = 16) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension Date {
    /// "Today", "Tomorrow", "Thu", "Nov 20" – compact due labels.
    func shortRelative(includeTime: Bool, calendar: Calendar = .current, now: Date = Date()) -> String {
        let time = includeTime ? " " + formatted(date: .omitted, time: .shortened) : ""
        if calendar.isDateInToday(self) { return includeTime ? formatted(date: .omitted, time: .shortened) : "Today" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" + time }
        if calendar.isDateInYesterday(self) { return "Yesterday" + time }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: self)).day ?? 0
        if days > 0 && days < 7 { return formatted(.dateTime.weekday(.abbreviated)) + time }
        let sameYear = calendar.component(.year, from: self) == calendar.component(.year, from: now)
        return (sameYear ? formatted(.dateTime.month(.abbreviated).day()) : formatted(.dateTime.month(.abbreviated).day().year())) + time
    }
}
