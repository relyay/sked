import Foundation
import Testing
@testable import VKSITCore

private func moscow(_ day: String, _ time: String) -> Date {
    CollegeClock.date(day: day, time: time)!
}

private let friday = Day(date: "2026-10-23", building: 1, groups: [
    GroupDay(group: "ИСП-225а", lessons: [
        Lesson(pair: 1, start: "08:30", end: "10:00", subject: "ОСиС", room: "17/1", subgroup: 1),
        Lesson(pair: 2, start: "10:10", end: "11:40", subject: "Ино. в проф.деят.", room: "119/1", subgroup: 2),
        Lesson(pair: 3, start: "12:10", end: "13:40", subject: "ПОПД", room: "24/1"),
        Lesson(pair: 4, start: "13:50", end: "15:20", subject: "ОСиС", room: "17/1", subgroup: 2),
    ]),
])
private let saturday = Day(date: "2026-10-24", building: 1, groups: [
    GroupDay(group: "ИСП-225а", lessons: [
        Lesson(pair: 5, start: "15:40", end: "17:10", subject: "ОСиС", isRemote: true, subgroup: 2, timeSource: "bells"),
    ], notes: [Note(kind: .startsAt, text: "Занятия начинаются с 11:10", time: "11:10", subgroup: 2)]),
])
private let monday = Day(date: "2026-10-26", building: 1, groups: [
    GroupDay(group: "ИСП-225а", lessons: [
        Lesson(pair: 2, start: "10:10", end: "11:40", subject: "ПОПД", room: "24/1"),
        Lesson(pair: 3, start: "12:10", end: "13:40", subject: "ПОПД", room: "24/1"),
    ]),
])
private let days = [monday, saturday, friday]

@Suite struct NextLessonTests {
    @Test func ongoingLesson() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        guard case .ongoing(let l) = q.current(at: moscow("2026-10-23", "09:00")) else {
            Issue.record("expected ongoing")
            return
        }
        #expect(l.lesson.pair == 1)
    }

    @Test func skipsOtherSubgroup() {
        // Subgroup 1 has nothing in pair 2, so after pair 1 the next is pair 3.
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        #expect(q.current(at: moscow("2026-10-23", "10:05")) == .upcoming(q.scheduled(friday.groups[0].lessons[2], on: friday)!))
    }

    @Test func breakBetweenPairsIsUpcoming() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .second)
        guard case .upcoming(let l) = q.current(at: moscow("2026-10-23", "10:00")) else {
            Issue.record("expected upcoming")
            return
        }
        #expect(l.lesson.pair == 2)
        #expect(l.start == moscow("2026-10-23", "10:10"))
    }

    @Test func finishedForToday() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        #expect(q.current(at: moscow("2026-10-23", "13:40")) == .finishedForToday)
    }

    @Test func noLessonsOnSunday() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        #expect(q.current(at: moscow("2026-10-25", "09:00")) == .noLessonsToday)
    }

    @Test func unknownGroupHasNoLessons() {
        let q = ScheduleQuery(days: days, group: "НЕТ-000", subgroup: .unspecified)
        #expect(q.current(at: moscow("2026-10-23", "09:00")) == .noLessonsToday)
    }

    @Test func otherSubgroupIsHidden() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        #expect(q.lessons(on: friday).map(\.pair) == [1, 3])
    }

    @Test func unspecifiedSubgroupSeesEverything() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .unspecified)
        #expect(q.lessons(on: friday).count == 4)
    }

    @Test func todayUsesMoscowNotDeviceZone() {
        // 23:30 in Moscow on Friday is already Saturday in Vladivostok.
        var vladivostok = Calendar(identifier: .gregorian)
        vladivostok.timeZone = TimeZone(identifier: "Asia/Vladivostok")!
        var calendar = CollegeClock.calendar
        calendar.locale = Locale(identifier: "ru_RU")
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first, calendar: calendar)
        let lateFriday = moscow("2026-10-23", "23:30")
        #expect(vladivostok.component(.day, from: lateFriday) == 24)
        #expect(q.day(for: lateFriday)?.date == "2026-10-23")
    }
}

@Suite struct NextSchoolDayTests {
    @Test func tomorrowWithLessons() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .second)
        let next = q.nextSchoolDay(after: moscow("2026-10-23", "18:00"))
        #expect(next?.day.date == "2026-10-24")
        #expect(next?.isTomorrow == true)
        #expect(next?.tomorrowIsFree == false)
    }

    @Test func tomorrowFreeForSubgroupSkipsToNextDay() {
        // Saturday only has a subgroup-2 lesson; subgroup 1 is free.
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        let next = q.nextSchoolDay(after: moscow("2026-10-23", "18:00"))
        #expect(next?.day.date == "2026-10-26")
        #expect(next?.isTomorrow == false)
        #expect(next?.tomorrowIsFree == true)
        #expect(next?.lessons.count == 2)
    }

    @Test func sundayLooksToMonday() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        let next = q.nextSchoolDay(after: moscow("2026-10-25", "12:00"))
        #expect(next?.day.date == "2026-10-26")
        #expect(next?.isTomorrow == true)
    }

    @Test func noFutureDays() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first)
        #expect(q.nextSchoolDay(after: moscow("2026-10-26", "08:00")) == nil)
    }

    @Test func startsAtFollowsSubgroup() {
        #expect(ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .second).startsAt(on: saturday) == "11:10")
        #expect(ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .first).startsAt(on: saturday) == nil)
    }

    @Test func nearestDayAfterLessonsIsNextSchoolDay() {
        let q = ScheduleQuery(days: days, group: "ИСП-225а", subgroup: .second)
        #expect(q.nearestDay(at: moscow("2026-10-23", "16:00"))?.date == "2026-10-24")
        #expect(q.nearestDay(at: moscow("2026-10-23", "09:00"))?.date == "2026-10-23")
    }
}

@Suite struct LunchTests {
    let day = Day(date: "2026-10-23", building: 1, groups: [
        GroupDay(group: "ДО-324", lessons: [], notes: [
            Note(kind: .lunch, text: "Обед 10:55-11:20", time: "10:55", endTime: "11:20", pair: 3, subgroup: 1),
            Note(kind: .lunch, text: "Обед 10:55-11:20", time: "10:55", endTime: "11:20", pair: 5, subgroup: 2),
            Note(kind: .lunch, text: "Обед 11:40-12:10", time: "11:40", endTime: "12:10", pair: 4, subgroup: 2),
            Note(kind: .startsAt, text: "Занятия начинаются с 11:10", time: "11:10"),
        ]),
    ])

    @Test func filtersBySubgroup() {
        let q = ScheduleQuery(days: [day], group: "ДО-324", subgroup: .first)
        #expect(q.lunches(on: day).map(\.time) == ["10:55"])
    }

    @Test func deduplicatesAcrossSubgroups() {
        let q = ScheduleQuery(days: [day], group: "ДО-324", subgroup: .unspecified)
        #expect(q.lunches(on: day).map(\.time) == ["10:55", "11:40"])
    }
}

@Suite struct FirstStartTests {
    @Test func mixedDayUsesFirstInPersonPair() {
        // Saturday of ИСП-225ис: remote pairs 1–2, PE in person from 11:50.
        let lessons = [
            Lesson(pair: 1, start: "09:00", subject: "ПОПД", isRemote: true, timeSource: "bells"),
            Lesson(pair: 2, start: "10:40", subject: "ПОПД", isRemote: true, timeSource: "bells"),
            Lesson(pair: 3, start: "11:50", subject: "Физ. культура", room: "СЗ/2", timeSource: "startsAt"),
        ]
        let first = ScheduleQuery.firstStart(of: lessons)
        #expect(first?.lesson.start == "11:50")
        #expect(first?.inPerson == true)
    }

    @Test func allRemoteUsesFirstPair() {
        let lessons = [
            Lesson(pair: 2, start: "10:10", subject: "ОСиС", isRemote: true),
            Lesson(pair: 1, start: "08:30", subject: "ОСиС", isRemote: true),
        ]
        #expect(ScheduleQuery.firstStart(of: lessons)?.lesson.pair == 1)
        #expect(ScheduleQuery.firstStart(of: lessons)?.inPerson == false)
    }

    @Test func allInPersonUsesFirstPair() {
        let lessons = [Lesson(pair: 2, start: "10:10", subject: "ПОПД", room: "24/1")]
        #expect(ScheduleQuery.firstStart(of: lessons)?.inPerson == false)
    }
}

@Suite struct BuildingTests {
    @Test func zeroBuildingFallsBackToDay() {
        #expect(Lesson(pair: 1, building: 0, start: "08:30", subject: "X").building(or: 2) == 2)
        #expect(Lesson(pair: 1, building: 1, start: "08:30", subject: "X").building(or: 2) == 1)
    }

    @Test func buildingComesFromLessons() {
        let day = Day(date: "2026-10-24", building: 1, groups: [
            GroupDay(group: "ИСП-225ис", lessons: [
                Lesson(pair: 1, building: 2, start: "09:00", subject: "ПОПД", isRemote: true),
                Lesson(pair: 3, building: 2, start: "11:50", subject: "Физ. культура", room: "СЗ/2"),
            ]),
        ])
        let q = ScheduleQuery(days: [day], group: "ИСП-225ис", subgroup: .unspecified)
        #expect(q.buildings(on: day) == [2])
    }
}

@Suite struct DecodingTests {
    @Test func decodesServerPayload() throws {
        let json = #"""
        {"group":"ЭСС-225","parsedAt":"2026-10-23T12:10:49.316279998+03:00",
         "sourceModified":"2026-10-23T08:52:17Z",
         "days":[{"date":"2026-10-24","weekday":"суббота","building":1,"groups":[{"group":"ЭСС-225",
           "lessons":[{"pair":1,"building":2,"pairTo":6,"start":"08:30","end":"18:50","subject":"Экзамен","isRemote":false,"timeSource":"bells"}],
           "notes":[{"kind":"somethingNew","text":"?"}]}]}]}
        """#
        let r = try JSONDecoder.vksit.decode(ScheduleResponse.self, from: Data(json.utf8))
        #expect(r.days[0].groups[0].lessons[0].pairLabel == "1–6")
        #expect(r.days[0].groups[0].notes?[0].kind == .other)
        #expect(r.days[0].groups[0].lessons[0].building == 2)
        #expect(abs(r.parsedAt.timeIntervalSince1970 - 1_792_746_649.316) < 0.01)
    }
}

@Suite struct ValidationTests {
    let groups = [GroupInfo(name: "ИСП-225а", course: 2, buildings: [1, 2])]

    @Test func requiresName() {
        var d = ProfileDraft()
        d.fullName = "   "
        d.group = "ИСП-225а"
        #expect(d.validate(availableGroups: groups) == .failure(.emptyName))
    }

    @Test func groupMustComeFromServerList() {
        var d = ProfileDraft()
        d.fullName = "Иванов Иван"
        d.group = "ИСП-999"
        #expect(d.validate(availableGroups: groups) == .failure(.unknownGroup))
        d.group = "ИСП-225а"
        d.subgroup = .second
        #expect(d.validate(availableGroups: groups) == .success(Profile(fullName: "Иванов Иван", group: "ИСП-225а", course: 2, subgroup: .second)))
    }

    @Test func serverAddress() {
        #expect(ServerAddress.default.baseURL?.absoluteString == "http://192.168.1.246:1984")
        #expect(ServerAddress.validate(host: "", port: "1984") == .failure(.emptyHost))
        #expect(ServerAddress.validate(host: "host", port: "0") == .failure(.invalidPort))
        #expect(ServerAddress.validate(host: "host", port: "65536") == .failure(.invalidPort))
        #expect(ServerAddress.validate(host: "my host", port: "80") == .failure(.invalidHost))
        #expect((try? ServerAddress.validate(host: "https://rasp.example.org/", port: "443").get())?.baseURL?.absoluteString == "https://rasp.example.org:443")
    }
}
