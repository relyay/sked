import SwiftUI
import VKSITCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
            }
            .background(ScreenBackground())
            .navigationTitle(greeting)
            .refreshable { await model.refresh() }
        }
    }

    private var greeting: String {
        let firstName = model.profile?.fullName.split(separator: " ").dropFirst().first ?? model.profile?.fullName.split(separator: " ").first
        return firstName.map { L("home.greeting \(String($0))") } ?? L("tab.home")
    }

    @ViewBuilder
    private var content: some View {
        switch model.scheduleState {
        case .idle, .loading:
            HomeSkeleton()
        case .failed(let error):
            ErrorStateView(error: error) { await model.refresh() }
                .frame(minHeight: 400)
        case .loaded:
            if let query = model.query {
                // Re-render every minute for the countdown.
                TimelineView(.everyMinute) { context in
                    HomeCards(query: query, now: context.date)
                }
            }
        }
    }
}

private struct HomeCards: View {
    @Environment(AppModel.self) private var model
    let query: ScheduleQuery
    let now: Date

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                if let reason = model.staleReason {
                    StaleDataBanner(fetchedAt: model.dataFetchedAt, reason: reason) { await model.refresh() }
                }
                CurrentLessonCard(state: query.current(at: now), now: now)
                NextDayCard(next: query.nextSchoolDay(after: now), now: now)
                if let day = query.nearestDay(at: now), let time = query.startsAt(on: day) {
                    StartsAtBanner(day: day, time: time, now: now)
                }
            }
        }
    }
}

private struct CurrentLessonCard: View {
    let state: CurrentLessonState
    let now: Date

    var body: some View {
        switch state {
        case .ongoing(let s):
            card(s, status: L("home.ongoing"), tint: .green)
        case .upcoming(let s):
            card(s, status: Format.countdown(from: now, to: s.start), tint: nil)
        case .finishedForToday:
            message(L("home.finished"), systemImage: "party.popper")
        case .noLessonsToday:
            message(L("home.noLessonsToday"), systemImage: "sun.max")
        }
    }

    private func card(_ s: ScheduledLesson, status: String, tint: Color?) -> some View {
        GlassCard(tint: tint) {
            Text(L("home.nextLesson"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(headline(s.lesson, building: s.lesson.building(or: s.day.building)))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let teacher = s.lesson.teacher {
                Text(teacher)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let subgroup = s.lesson.subgroup {
                SubgroupBadge(subgroup: subgroup)
            }
            Label(status, systemImage: tint == nil ? "clock" : "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(tint ?? .accentColor)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([L("home.nextLesson"), Format.accessibilityLabel(s.lesson), status].joined(separator: ", "))
        .accessibilityIdentifier("home.currentLesson")
    }

    /// "2 пара · ОБиЗР · 14:30 · корпус 2, каб. 15/2".
    private func headline(_ lesson: Lesson, building: Int) -> String {
        var parts = [L("lesson.pairNumber \(lesson.pairLabel)"), lesson.subject, lesson.start]
        if lesson.isRemote {
            parts.append(L("lesson.remote"))
        } else if let room = lesson.room {
            parts.append(L("home.buildingRoom \(building) \(room)"))
        } else {
            parts.append(Format.building(building))
        }
        return parts.joined(separator: " · ")
    }

    private func message(_ text: String, systemImage: String) -> some View {
        GlassCard {
            Label(text, systemImage: systemImage)
                .font(.title3.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.currentLesson")
    }
}

private struct NextDayCard: View {
    let next: NextSchoolDay?
    let now: Date

    var body: some View {
        GlassCard {
            Text(L("home.nextDay"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let next {
                if next.tomorrowIsFree && !next.isTomorrow {
                    Text(L("home.tomorrowFree"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(summary(next))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(L("home.noNextDay"), systemImage: "calendar.badge.clock")
                    .font(.title3.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.nextDay")
    }

    /// "Завтра (сб) · 4 пары · корпус 1 · первая в 12:10".
    private func summary(_ next: NextSchoolDay) -> String {
        let weekday = Format.chip(next.day).weekday.lowercased()
        let title = next.isTomorrow ? L("home.tomorrowWeekday \(weekday)") : Format.shortDay(next.day)
        let buildings = ScheduleQuery.buildings(of: next.lessons, fallback: next.day.building)
        var parts = [title, Format.lessonCount(next.lessons.count), Format.buildings(buildings)]
        if let first = ScheduleQuery.firstStart(of: next.lessons) {
            parts.append(first.inPerson ? L("home.firstInPersonAt \(first.lesson.start)") : L("home.firstAt \(first.lesson.start)"))
        }
        return parts.joined(separator: " · ")
    }
}

private struct StartsAtBanner: View {
    let day: Day
    let time: String
    let now: Date

    var body: some View {
        GlassCard(tint: .yellow) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("home.startsAt \(time)"))
                        .font(.headline)
                    Text(Format.relativeDay(day, now: now) ?? Format.longDay(day))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "alarm")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HomeSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in
                GlassCard {
                    Text("Следующая пара")
                        .font(.caption)
                    Text("2 пара · Предмет · 14:30 · корпус 2")
                        .font(.title3)
                    Text("начнётся через 2 ч 13 мин")
                }
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel(L("a11y.loading"))
    }
}
