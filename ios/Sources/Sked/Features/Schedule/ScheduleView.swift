import SwiftUI
import SkedCore

struct ScheduleView: View {
    enum Mode: Hashable {
        case day, week
    }

    @Environment(AppModel.self) private var model
    @State private var mode = Mode.day
    @State private var selectedDate: String?

    var body: some View {
        NavigationStack {
            Group {
                switch model.scheduleState {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let error):
                    ErrorStateView(error: error) { await model.refresh() }
                case .loaded:
                    if let query = model.query {
                        TimelineView(.everyMinute) { context in
                            content(query: query, now: context.date)
                        }
                    }
                }
            }
            .background(ScreenBackground())
            .navigationTitle(L("tab.schedule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(L("schedule.mode"), selection: $mode) {
                        Text(L("schedule.day")).tag(Mode.day)
                        Text(L("schedule.week")).tag(Mode.week)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
    }

    @ViewBuilder
    private func content(query: ScheduleQuery, now: Date) -> some View {
        let days = query.upcomingDays(from: now)
        if days.isEmpty {
            ContentUnavailableView(L("schedule.noDays"), systemImage: "calendar.badge.exclamationmark", description: Text(L("schedule.noDaysHint")))
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    if let reason = model.staleReason {
                        StaleDataBanner(fetchedAt: model.dataFetchedAt, reason: reason) { await model.refresh() }
                    }
                    switch mode {
                    case .day:
                        DayScheduleView(query: query, days: days, selectedDate: $selectedDate, now: now)
                    case .week:
                        WeekScheduleView(query: query, days: days, now: now)
                    }
                }
                .padding()
            }
            .refreshable { await model.refresh() }
        }
    }
}

private struct DayScheduleView: View {
    let query: ScheduleQuery
    let days: [Day]
    @Binding var selectedDate: String?
    let now: Date

    private var day: Day {
        days.first { $0.date == selectedDate } ?? days[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DateChips(days: days, selected: day.date, now: now) { selectedDate = $0 }

            Text(title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)

            if day.date == CollegeClock.dayString(now), let next = query.nextLessonToday(after: now) {
                GlassCard(tint: .accentColor) {
                    Label(
                        [L("schedule.next"), L("lesson.pairNumber \(next.lesson.pairLabel)"), Format.countdown(from: now, to: next.start)]
                            .joined(separator: " · "),
                        systemImage: "clock"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            }

            DayNotes(startsAt: query.startsAt(on: day), lunches: query.lunches(on: day))

            let lessons = query.lessons(on: day)
            if lessons.isEmpty {
                ContentUnavailableView(L("schedule.empty"), systemImage: "cup.and.saucer")
            } else {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(lessons) { lesson in
                            LessonRow(lesson: lesson)
                        }
                    }
                }
            }
        }
    }

    /// "Пятница, 23 октября · сегодня · корпус 2".
    private var title: String {
        [Format.longDay(day), Format.relativeDay(day, now: now), Format.buildings(query.buildings(on: day))]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct DateChips: View {
    let days: [Day]
    let selected: String
    let now: Date
    var select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(days) { day in
                        let chip = Format.chip(day)
                        let isSelected = day.date == selected
                        Button {
                            select(day.date)
                        } label: {
                            VStack(spacing: 2) {
                                Text(chip.weekday)
                                    .font(.caption)
                                Text(chip.number)
                                    .font(.title3.weight(.semibold).monospacedDigit())
                            }
                            .frame(minWidth: 44)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(isSelected ? .regular.tint(Color.accentColor.opacity(0.45)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 16))
                        .accessibilityLabel([Format.longDay(day), Format.relativeDay(day, now: now)].compactMap { $0 }.joined(separator: ", "))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }
}

private struct WeekScheduleView: View {
    let query: ScheduleQuery
    let days: [Day]
    let now: Date

    var body: some View {
        LazyVStack(spacing: 14) {
            ForEach(days) { day in
                GlassCard {
                    Text(header(day))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    DayNotes(startsAt: query.startsAt(on: day), lunches: query.lunches(on: day), font: .footnote)
                    let lessons = query.lessons(on: day)
                    if lessons.isEmpty {
                        Label(L("schedule.empty"), systemImage: "cup.and.saucer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(lessons) { lesson in
                            CompactLessonRow(lesson: lesson)
                        }
                    }
                }
            }
        }
    }

    /// "Пт, 23.10 · сегодня · 2 корпус".
    private func header(_ day: Day) -> String {
        [Format.shortDay(day), Format.relativeDay(day, now: now), Format.buildings(query.buildings(on: day))]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
