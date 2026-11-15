import SwiftUI
import ThoughtCloudKit

struct ReviewScreen: View {
    @Environment(AppState.self) private var app
    @Environment(Library.self) private var library
    @State private var filter: UUID?
    @State private var session: ReviewSession?
    @State private var dragOffset: CGSize = .zero
    @State private var flyOut: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if let session {
                    Text(subtitle(session))
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                let counts = ReviewSession.dueCounts(in: library)
                CategoryFilterBar(
                    categories: library.categories.filter { (counts.byCategory[$0.id] ?? 0) > 0 || $0.id == filter },
                    selection: $filter,
                    counts: counts.byCategory,
                    allTitle: "All due",
                    allCount: counts.total
                )
                if let session {
                    if let current = session.current {
                        stack(session: session, current: current)
                        buttons(session: session)
                    } else {
                        finished(session: session)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .background(Theme.background)
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let session, session.canUndo {
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            withAnimation(.snappy) { session.undo() }
                        }
                    }
                }
            }
            .onAppear {
                if let focus = app.reviewFocus {
                    filter = focus
                    app.reviewFocus = nil
                }
                if session == nil || session!.isFinished { restart() }
            }
            .onChange(of: filter) { restart() }
        }
    }

    private func subtitle(_ session: ReviewSession) -> String {
        if session.mode == .browseAll { return "Browsing · \(session.remaining) left" }
        return session.isFinished ? "Done for now" : "\(session.remaining) to go over"
    }

    private func restart(mode: ReviewSession.Mode = .due) {
        session = ReviewSession(library: library, categoryID: filter, mode: mode)
        dragOffset = .zero
    }

    // MARK: - Stack

    private func stack(session: ReviewSession, current: Item) -> some View {
        ZStack {
            ForEach(Array(session.upcoming(2).enumerated().reversed()), id: \.element.id) { offset, item in
                ReviewCardView(item: item, position: session.index + offset + 2, total: session.queue.count)
                    .scaleEffect(1 - CGFloat(offset + 1) * 0.045)
                    .offset(y: CGFloat(offset + 1) * 12)
                    .allowsHitTesting(false)
            }
            ReviewCardView(item: current, position: session.index + 1, total: session.queue.count, swipe: dragOffset.width)
                .offset(x: dragOffset.width + flyOut, y: dragOffset.height * 0.3)
                .rotationEffect(.degrees(Double(dragOffset.width + flyOut) / 18))
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation }
                        .onEnded { value in
                            let dx = value.translation.width + value.predictedEndTranslation.width * 0.2
                            if abs(dx) > 110 {
                                fling(session, dx > 0 ? .gotIt : .again)
                            } else {
                                withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                            }
                        }
                )
                .id(current.id)
        }
        .padding(.horizontal)
        .frame(maxHeight: 440)
    }

    private func fling(_ session: ReviewSession, _ grade: ReviewGrade) {
        let direction: CGFloat = grade == .gotIt ? 1 : -1
        withAnimation(.easeIn(duration: 0.2)) { flyOut = direction * 500 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            session.swipe(grade)
            flyOut = 0
            dragOffset = .zero
        }
    }

    private func buttons(session: ReviewSession) -> some View {
        HStack(spacing: 10) {
            gradeButton("Show again", "← ", gap: session.nextGapDays(for: .again), color: Theme.danger) { fling(session, .again) }
            gradeButton("Got it", "", trailing: " →", gap: session.nextGapDays(for: .gotIt),
                        retires: session.current.map { library.retiresAfterGotIt($0.id) } ?? false,
                        color: Theme.success) { fling(session, .gotIt) }
        }
        .padding(.horizontal)
        .sensoryFeedback(.impact(weight: .light), trigger: session.index)
    }

    private func gradeButton(_ title: String, _ leading: String, trailing: String = "", gap: Int?, retires: Bool = false, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(leading + title + trailing).font(.subheadline.weight(.semibold))
                if session?.mode == .due, retires {
                    Text("done").font(.caption2).opacity(0.75)
                } else if session?.mode == .due, let gap {
                    Text(gap == 1 ? "tomorrow" : "in \(gap) days").font(.caption2).opacity(0.75)
                } else {
                    Text("practice").font(.caption2).opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Finished

    private func finished(session: ReviewSession) -> some View {
        let hasCards = !library.reviewableItems().isEmpty
        return VStack(spacing: 12) {
            Text("🎉").font(.system(size: 48))
            Text(hasCards ? "All caught up" : "No review cards yet").font(.title3.weight(.semibold))
            if hasCards {
                Text(nextDueText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                Button("Browse all") { restart(mode: .browseAll) }
                    .buttonStyle(.bordered)
                    .tint(ItemKind.review.color)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var nextDueText: String {
        let next = library.reviewableItems(inCategory: filter)
            .compactMap { $0.review?.nextReviewAt }
            .filter { $0 > library.now }
            .min()
        guard let next else { return "Nothing scheduled." }
        return "Next card comes back " + next.shortRelative(includeTime: false).lowercased() + "."
    }
}

struct ReviewCardView: View {
    @Environment(Library.self) private var library
    @Environment(AppState.self) private var app
    let item: Item
    let position: Int
    let total: Int
    var swipe: CGFloat = 0

    var body: some View {
        let style = library.style(for: item)
        let accent = style.primary
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryPills(style: style, compact: true)
                Spacer()
                if let seen = item.review?.seenCount, seen > 0 {
                    Text("seen \(seen)×").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            if item.kind == .event, let event = item.event {
                eventHeader(event)
            } else {
                Text(item.displayTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.body.isEmpty {
                ScrollView { BodyView(item.body, accent: accent).frame(maxWidth: .infinity, alignment: .leading) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            Spacer(minLength: 0)
            HStack {
                if let event = item.event, item.kind == .event {
                    if event.addToCalendar {
                        Label("In Calendar", systemImage: event.calendarEventID == nil ? "calendar.badge.clock" : "calendar.badge.checkmark")
                    }
                } else if let until = item.review?.rememberUntil {
                    Label("Until " + until.shortRelative(includeTime: false), systemImage: "calendar")
                } else {
                    Text("No end date")
                }
                Spacer()
                Text("\(position) / \(total)")
            }
            .font(.caption)
            .foregroundStyle(Theme.dim)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 420, alignment: .topLeading)
        .background(
            LinearGradient(colors: [accent.opacity(0.22), Theme.card], startPoint: .topLeading, endPoint: .center)
        )
        .background(Theme.card)
        .overlay(alignment: .top) { CategoryStripe(style: style, height: 4) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(accent.opacity(0.3), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) { stamp("GOT IT", Theme.success, opacity: swipe / 100, angle: -12) }
        .overlay(alignment: .topTrailing) { stamp("AGAIN", Theme.danger, opacity: -swipe / 100, angle: 12) }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        .onTapGesture(count: 2) { app.detailItemID = item.id }
    }

    private func eventHeader(_ event: EventInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                DateTile(date: event.start, size: .large)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(event.timeText).font(.subheadline).foregroundStyle(Theme.dim)
                }
            }
            Text(event.countdownText(now: library.now, calendar: library.calendar))
                .font(.title.weight(.bold))
                .foregroundStyle(ItemKind.event.color)
        }
    }

    private func stamp(_ text: String, _ color: Color, opacity: CGFloat, angle: Double) -> some View {
        Text(text)
            .font(.headline.weight(.heavy))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 2.5))
            .foregroundStyle(color)
            .rotationEffect(.degrees(angle))
            .padding(24)
            .opacity(max(0, min(1, opacity)))
    }
}
