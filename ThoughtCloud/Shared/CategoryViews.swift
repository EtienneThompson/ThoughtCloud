import SwiftUI
import ThoughtCloudKit

/// Pills for an item's categories (or Inbox).
struct CategoryPills: View {
    let style: CategoryStyle
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if case .inbox = style {
                pill("📥", "Inbox", Color(hex: CategoryPalette.inboxHex))
            } else if compact, style.categories.count >= 3 {
                pill(style.emojis, "\(style.categories.count) categories", Theme.text)
            } else {
                ForEach(style.categories) { category in
                    pill(category.emoji, category.name, Color(hex: category.colorHex))
                }
            }
        }
    }

    private func pill(_ emoji: String, _ name: String, _ color: Color) -> some View {
        Text("\(emoji) \(name)")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct KindPill: View {
    let kind: ItemKind
    var body: some View {
        Label(kind.label, systemImage: kind.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(kind.color.opacity(0.18), in: Capsule())
            .foregroundStyle(kind.color)
    }
}

/// Thin top stripe for cards: solid, split gradient, or white for "many".
struct CategoryStripe: View {
    let style: CategoryStyle
    var height: CGFloat = 3
    var body: some View {
        Rectangle().fill(style.gradient).frame(height: height)
    }
}

/// A selectable chip used in capture, filters and editors.
struct Chip: View {
    let title: String
    var color: Color = Theme.text
    var isOn = false
    var count: Int?
    var dashed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                if let count { Text("\(count)").opacity(0.6) }
            }
            .font(.footnote.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? color : Theme.dim)
            .background(isOn ? color.opacity(0.16) : Theme.card2, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isOn ? color : .clear, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
            }
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal category filter used by Todos, Thoughts and Review.
struct CategoryFilterBar: View {
    let categories: [ItemCategory]
    @Binding var selection: UUID?
    var counts: [UUID: Int] = [:]
    var allTitle = "All"
    var allCount: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: allTitle, isOn: selection == nil, count: allCount) { selection = nil }
                ForEach(categories) { category in
                    Chip(title: "\(category.emoji) \(category.name)", color: Color(hex: category.colorHex), isOn: selection == category.id, count: counts[category.id]) {
                        selection = selection == category.id ? nil : category.id
                    }
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(Theme.dim)
            Text(title).font(.headline)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}
