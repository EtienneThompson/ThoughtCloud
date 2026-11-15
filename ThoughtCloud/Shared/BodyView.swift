import SwiftUI
import ThoughtCloudKit

/// Renders an item body with the light formatting rules from `BodyFormatter`.
struct BodyView: View {
    let body_: String
    var accent: Color = Theme.accent
    var font: Font = .callout

    init(_ body: String, accent: Color = Theme.accent, font: Font = .callout) {
        self.body_ = body
        self.accent = accent
        self.font = font
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(BodyFormatter.blocks(from: body_).enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
        .font(font)
        .foregroundStyle(Theme.text.opacity(0.88))
    }

    @ViewBuilder
    private func row(_ block: BodyBlock) -> some View {
        switch block {
        case .text(let text):
            Text(text)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                labeledOrPlain(text)
            }
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number).font(font.weight(.semibold)).foregroundStyle(accent).frame(minWidth: 16, alignment: .leading)
                labeledOrPlain(text)
            }
        case .labeled(let label, let value):
            labeled(label, value)
        }
    }

    @ViewBuilder
    private func labeledOrPlain(_ text: String) -> some View {
        if let (label, value) = BodyFormatter.labelValue(text) {
            labeled(label, value)
        } else {
            Text(text)
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(font.weight(.semibold)).foregroundStyle(accent).frame(minWidth: 56, alignment: .leading)
            Text(value)
        }
    }
}
