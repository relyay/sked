import SwiftUI
import SkedCore

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
            message(L("home.finished"))
        case .noLessonsToday:
            message(L("home.noLessonsToday"))
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
            Text(status)
                .font(.headline)
                .foregroundStyle(tint ?? .accentColor)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([L("home.nextLesson"), Format.accessibilityLabel(s.lesson), status].joined(separator: ", "))
        .accessibilityIdentifier("home.currentLesson")
    }

    /// "Class 2 · ОБиЗР · 14:30 · building 2, room 15/2".
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

    private func message(_ text: String) -> some View {
        GlassCard {
            Text(text)
                .font(.title3.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.currentLesson")
    }
}

private struct HomeSkeleton: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in
                GlassCard {
                    Text("Next class")
                        .font(.caption)
                    Text("Class 2 · Subject · 14:30 · building 2")
                        .font(.title3)
                    Text("starts in 2 hr 13 min")
                }
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel(L("a11y.loading"))
    }
}
