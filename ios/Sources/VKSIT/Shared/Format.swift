import Foundation
import VKSITCore

/// User-facing formatting of schedule data.
enum Format {
    static var locale: Locale { .autoupdatingCurrent }

    /// "08:30 – 10:00".
    static func timeRange(_ lesson: Lesson) -> String {
        lesson.end.map { "\(lesson.start) – \($0)" } ?? lesson.start
    }

    /// "каб. 15/2 · Петров С.И." or "дистант · Петров С.И.".
    static func place(_ lesson: Lesson) -> String {
        var parts: [String] = []
        if lesson.isRemote {
            parts.append(L("lesson.remote"))
        } else if let room = lesson.room {
            parts.append(L("lesson.room \(room)"))
        }
        if let teacher = lesson.teacher { parts.append(teacher) }
        return parts.joined(separator: " · ")
    }

    static func accessibilityLabel(_ lesson: Lesson) -> String {
        var parts = [L("lesson.pairNumber \(lesson.pairLabel)"), lesson.subject, timeRange(lesson), place(lesson)]
        if let subgroup = lesson.subgroup { parts.append(L("subgroup.badge \(subgroup)")) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// "через 2 ч 13 мин"; rounds up so it never says "через 0 мин".
    static func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let duration = Duration.seconds(minutes * 60)
        let text = duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated).locale(locale))
        return L("countdown.in \(text)")
    }

    static func building(_ number: Int) -> String {
        L("building.short \(number)")
    }

    /// "корпус 1" or "корпуса 1, 2" when a day spans both.
    static func buildings(_ numbers: [Int]) -> String {
        guard numbers.count > 1 else { return building(numbers.first ?? 0) }
        return L("building.many \(numbers.map(String.init).joined(separator: ", "))")
    }

    private static func dayDate(_ day: Day) -> Date {
        CollegeClock.date(day: day.date) ?? .now
    }

    private static var dayStyle: Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: CollegeClock.calendar, timeZone: CollegeClock.timeZone)
        style = style.weekday(.wide).day().month(.wide)
        return style
    }

    /// "Пятница, 23 октября".
    static func longDay(_ day: Day) -> String {
        dayDate(day).formatted(dayStyle).capitalizedFirst
    }

    /// "Пт, 23.10".
    static func shortDay(_ day: Day) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: CollegeClock.calendar, timeZone: CollegeClock.timeZone)
        let weekday = dayDate(day).formatted(style.weekday(.abbreviated)).capitalizedFirst
        let date = dayDate(day).formatted(style.day(.twoDigits).month(.twoDigits))
        return "\(weekday), \(date)"
    }

    /// Chip label: weekday on top, day number below.
    static func chip(_ day: Day) -> (weekday: String, number: String) {
        let style = Date.FormatStyle(locale: locale, calendar: CollegeClock.calendar, timeZone: CollegeClock.timeZone)
        return (dayDate(day).formatted(style.weekday(.abbreviated)).capitalizedFirst, dayDate(day).formatted(style.day()))
    }

    /// "сегодня" / "завтра" relative to now, or nil.
    static func relativeDay(_ day: Day, now: Date) -> String? {
        let calendar = CollegeClock.calendar
        let today = CollegeClock.dayString(now)
        let tomorrow = CollegeClock.dayString(calendar.date(byAdding: .day, value: 1, to: now)!)
        switch day.date {
        case today: return L("day.today")
        case tomorrow: return L("day.tomorrow")
        default: return nil
        }
    }

    static func lessonCount(_ count: Int) -> String {
        L("lessons.count \(count)")
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
