import SwiftUI
import ThoughtCloudKit

/// Calendar-style day tile: month (or weekday) band over the day number.
struct DateTile: View {
    enum Size { case small, large }
    let date: Date
    var size: Size = .small

    var body: some View {
        let large = size == .large
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: large ? 11 : 9, weight: .heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(ItemKind.event.color)
                .foregroundStyle(.black)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: large ? 26 : 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.top, large ? 2 : 1)
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: large ? 10 : 8, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.bottom, large ? 5 : 3)
        }
        .frame(width: large ? 58 : 42)
        .background(Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: large ? 12 : 9, style: .continuous))
    }
}
