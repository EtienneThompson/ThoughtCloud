import SwiftUI
import ThoughtCloudKit

struct EventsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library

    var body: some View {
        NavigationStack {
            let sectioner = EventSectioner(calendar: library.calendar)
            let groups = sectioner.sections(for: library.upcomingEvents(), now: library.now)
            ScrollView {
                if groups.isEmpty {
                    EmptyStateView(symbol: "calendar", title: "No upcoming events")
                        .padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(groups, id: \.section) { group in
                            Text(title(for: group.section))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.dim)
                                .padding(.top, 12)
                                .padding(.leading, 4)
                            ForEach(group.items) { item in
                                EventRow(item: item)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background)
            .navigationTitle("Events")
        }
    }

    private func title(for section: EventSection) -> String {
        switch section {
        case .thisWeek: return "THIS WEEK"
        case .laterThisMonth: return "LATER THIS MONTH"
        case .month(let year, let month):
            let date = library.calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? library.now
            let sameYear = library.calendar.component(.year, from: library.now) == year
            return date.formatted(sameYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year()).uppercased()
        }
    }
}

struct EventRow: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    let item: Item

    var body: some View {
        if let event = item.event {
            let style = library.style(for: item)
            Button { app.detailItemID = item.id } label: {
                HStack(spacing: 12) {
                    DateTile(date: event.start)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if style != .inbox {
                                Circle().fill(style.gradient).frame(width: 7, height: 7)
                            }
                            Text(event.timeText)
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 4)
                    Text(event.shortCountdown(now: library.now, calendar: library.calendar))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ItemKind.event.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Open", systemImage: "square.and.pencil") { app.detailItemID = item.id }
                Button("Archive", systemImage: "archivebox") { library.setArchived(item.id, true) }
                Button("Delete", systemImage: "trash", role: .destructive) { library.delete(item.id) }
            }
        }
    }
}
