import Foundation
import SkedCore

/// User-facing formatting of schedule data.
enum Format {
    /// The locale for the language our strings resolved to. `Locale.current`
    /// can stay English when iOS does not treat the app as localized, so it is
    /// derived from the module bundle instead; the region is kept.
    static let locale: Locale = {
        let language = Bundle.module.preferredLocalizations.first ?? "ru"
        let region = Locale.current.region?.identifier ?? (language == "ru" ? "RU" : "US")
        return Locale(identifier: "\(language)_\(region)")
    }()

    /// "Oct 23, 2026 at 12:29".
    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
    }

    /// "08:30 – 10:00".
    static func timeRange(_ lesson: Lesson) -> String {
        lesson.end.map { "\(lesson.start) – \($0)" } ?? lesson.start
    }

    /// "Lunch 10:55–11:20", or "Lunch from 10:55" when the PDF gives no end.
    static func lunch(_ note: Note) -> String {
        guard let time = note.time else { return note.text }
        return note.endTime.map { L("lunch.range \(time) \($0)") } ?? L("lunch.from \(time)")
    }

    /// "room 15/2 · Петров С.И." or "remote · Петров С.И.".
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

    /// "starts in 2 hr 13 min"; rounds up so it never says "in 0 min".
    static func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let duration = Duration.seconds(minutes * 60)
        let text = duration.formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated).locale(locale))
        return L("countdown.in \(text)")
    }

    static func building(_ number: Int) -> String {
        L("building.short \(number)")
    }

    /// "building 1" or "buildings 1, 2" when a day spans both.
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

    /// "Friday, October 23".
    static func longDay(_ day: Day) -> String {
        dayDate(day).formatted(dayStyle).capitalizedFirst
    }

    /// "Fri, 23.10".
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

    /// "today" / "tomorrow" relative to now, or nil.
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
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
