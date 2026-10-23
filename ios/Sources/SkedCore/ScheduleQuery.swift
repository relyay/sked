import Foundation

/// The college works on Moscow time; "today" is computed with the device
/// calendar pinned to Europe/Moscow so travel or a misconfigured zone does not
/// shift the schedule.
public enum CollegeClock {
    public static let timeZone = TimeZone(identifier: "Europe/Moscow")!

    public static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    /// "YYYY-MM-DD" of `date` in Moscow.
    public static func dayString(_ date: Date, calendar: Calendar = calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Midnight in Moscow of a "YYYY-MM-DD" string.
    public static func date(day: String, calendar: Calendar = calendar) -> Date? {
        date(day: day, time: "00:00", calendar: calendar)
    }

    /// A Moscow wall-clock time on a given day.
    public static func date(day: String, time: String, calendar: Calendar = calendar) -> Date? {
        let d = day.split(separator: "-").compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 2 else { return nil }
        return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]))
    }
}

/// A lesson placed on the timeline.
public struct ScheduledLesson: Hashable, Sendable, Identifiable {
    public var lesson: Lesson
    public var day: Day
    public var start: Date
    public var end: Date

    public var id: String { day.date + "/" + lesson.id }
}

/// What the "next pair" card shows.
public enum CurrentLessonState: Equatable, Sendable {
    case ongoing(ScheduledLesson)
    case upcoming(ScheduledLesson)
    /// Today had lessons and all of them are over.
    case finishedForToday
    /// No lessons today at all (weekend or empty day).
    case noLessonsToday
}

/// The "next school day" card.
public struct NextSchoolDay: Equatable, Sendable {
    public var day: Day
    public var lessons: [Lesson]
    public var isTomorrow: Bool
    /// Tomorrow exists in the calendar but has no lessons for the user.
    public var tomorrowIsFree: Bool
}

/// Answers schedule questions for one group and subgroup.
public struct ScheduleQuery: Sendable {
    public var days: [Day]
    public var group: String
    public var subgroup: Subgroup
    public var calendar: Calendar

    /// A lesson without an end time lasts a standard pair.
    static let defaultLength: TimeInterval = 90 * 60

    public init(days: [Day], group: String, subgroup: Subgroup, calendar: Calendar = CollegeClock.calendar) {
        self.days = days.sorted { $0.date < $1.date }
        self.group = group
        self.subgroup = subgroup
        self.calendar = calendar
    }

    public func groupDay(on day: Day) -> GroupDay? {
        day.groups.first { $0.group == group }
    }

    /// Lessons the user attends: whole-group ones plus their subgroup's. With
    /// no subgroup chosen, everything is shown.
    public func lessons(on day: Day) -> [Lesson] {
        (groupDay(on: day)?.lessons ?? []).filter(isVisible).sorted {
            ($0.pair, $0.subgroup ?? 0) < ($1.pair, $1.subgroup ?? 0)
        }
    }

    public func isVisible(_ lesson: Lesson) -> Bool {
        subgroup == .unspecified || lesson.subgroup == nil || lesson.subgroup == subgroup.rawValue
    }


    /// Buildings the user goes to on a day, from the lessons themselves.
    public func buildings(on day: Day) -> [Int] {
        Self.buildings(of: lessons(on: day), fallback: day.building)
    }

    public static func buildings(of lessons: [Lesson], fallback: Int) -> [Int] {
        let set = Set(lessons.map { $0.building(or: fallback) })
        return set.isEmpty ? [fallback] : set.sorted()
    }

    /// When the user has to be at college: the first in-person pair if the day
    /// has one (remote pairs on mixed days carry no printed time), otherwise
    /// the first pair.
    public static func firstStart(of lessons: [Lesson]) -> (lesson: Lesson, inPerson: Bool)? {
        let timed = lessons.filter { !$0.start.isEmpty }.sorted { ($0.start, $0.pair) < ($1.start, $1.pair) }
        if timed.contains(where: \.isRemote), let inPerson = timed.first(where: { !$0.isRemote }) {
            return (inPerson, true)
        }
        return timed.first.map { ($0, false) }
    }

    /// Lunch breaks for the user's subgroup, without duplicates (the PDF often
    /// repeats the same lunch in both subgroup columns), earliest first.
    public func lunches(on day: Day) -> [Note] {
        var seen = Set<String>()
        return (groupDay(on: day)?.notes ?? [])
            .filter { note in
                note.kind == .lunch && note.time != nil
                    && (subgroup == .unspecified || note.subgroup == nil || note.subgroup == subgroup.rawValue)
            }
            .filter { seen.insert("\($0.time ?? "")-\($0.endTime ?? "")").inserted }
            .sorted { ($0.time ?? "") < ($1.time ?? "") }
    }

    /// "Classes start at …" («Занятия начинаются с …») for the user's subgroup.
    public func startsAt(on day: Day) -> String? {
        groupDay(on: day)?.notes?.first { note in
            note.kind == .startsAt && (subgroup == .unspecified || note.subgroup == nil || note.subgroup == subgroup.rawValue)
        }?.time
    }

    public func day(for date: Date) -> Day? {
        let key = CollegeClock.dayString(date, calendar: calendar)
        return days.first { $0.date == key }
    }

    /// Days from today on, as far as the PDF goes.
    public func upcomingDays(from now: Date) -> [Day] {
        let today = CollegeClock.dayString(now, calendar: calendar)
        return days.filter { $0.date >= today }
    }

    public func scheduled(_ lesson: Lesson, on day: Day) -> ScheduledLesson? {
        guard let start = CollegeClock.date(day: day.date, time: lesson.start, calendar: calendar) else { return nil }
        let end = lesson.end.flatMap { CollegeClock.date(day: day.date, time: $0, calendar: calendar) }
            ?? start.addingTimeInterval(Self.defaultLength)
        return ScheduledLesson(lesson: lesson, day: day, start: start, end: end)
    }

    public func current(at now: Date) -> CurrentLessonState {
        guard let today = day(for: now) else { return .noLessonsToday }
        let timeline = lessons(on: today).compactMap { scheduled($0, on: today) }.sorted { $0.start < $1.start }
        guard !timeline.isEmpty else { return .noLessonsToday }
        if let ongoing = timeline.first(where: { $0.start <= now && now < $0.end }) {
            return .ongoing(ongoing)
        }
        if let next = timeline.first(where: { $0.start > now }) {
            return .upcoming(next)
        }
        return .finishedForToday
    }

    /// The next upcoming lesson after `now`, today only.
    public func nextLessonToday(after now: Date) -> ScheduledLesson? {
        guard let today = day(for: now) else { return nil }
        return lessons(on: today).compactMap { scheduled($0, on: today) }
            .filter { $0.start > now }
            .min { $0.start < $1.start }
    }

    /// The first day after today with lessons for the user.
    public func nextSchoolDay(after now: Date) -> NextSchoolDay? {
        let today = CollegeClock.dayString(now, calendar: calendar)
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let tomorrow = CollegeClock.dayString(tomorrowDate, calendar: calendar)
        let tomorrowHasLessons = days.first { $0.date == tomorrow }.map { !lessons(on: $0).isEmpty } ?? false

        for day in days where day.date > today {
            let lessons = lessons(on: day)
            if !lessons.isEmpty {
                return NextSchoolDay(day: day, lessons: lessons, isTomorrow: day.date == tomorrow, tomorrowIsFree: !tomorrowHasLessons)
            }
        }
        return nil
    }

    /// The day the "classes start at" banner should describe: today if it
    /// still has lessons ahead, otherwise the next school day.
    public func nearestDay(at now: Date) -> Day? {
        switch current(at: now) {
        case .ongoing(let l), .upcoming(let l): l.day
        case .finishedForToday, .noLessonsToday: nextSchoolDay(after: now)?.day
        }
    }
}
