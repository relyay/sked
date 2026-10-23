package ru.sked.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import ru.sked.app.data.Json
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

// Mirrors ios/Tests/SkedCoreTests so both clients follow the same rules.

private fun moscow(day: String, time: String): Instant = CollegeClock.instant(day, time)!!

private val friday = Day("2026-10-23", building = 1, groups = listOf(
    GroupDay("ИСП-225а", listOf(
        Lesson(pair = 1, start = "08:30", end = "10:00", subject = "ОСиС", room = "17/1", subgroup = 1),
        Lesson(pair = 2, start = "10:10", end = "11:40", subject = "Ино. в проф.деят.", room = "119/1", subgroup = 2),
        Lesson(pair = 3, start = "12:10", end = "13:40", subject = "ПОПД", room = "24/1"),
        Lesson(pair = 4, start = "13:50", end = "15:20", subject = "ОСиС", room = "17/1", subgroup = 2),
    )),
))
private val saturday = Day("2026-10-24", building = 1, groups = listOf(
    GroupDay(
        "ИСП-225а",
        listOf(Lesson(pair = 5, start = "15:40", end = "17:10", subject = "ОСиС", isRemote = true, subgroup = 2, timeSource = "bells")),
        listOf(Note(Note.Kind.STARTS_AT, "Занятия начинаются с 11:10", time = "11:10", subgroup = 2)),
    ),
))
private val monday = Day("2026-10-26", building = 1, groups = listOf(
    GroupDay("ИСП-225а", listOf(
        Lesson(pair = 2, start = "10:10", end = "11:40", subject = "ПОПД", room = "24/1"),
        Lesson(pair = 3, start = "12:10", end = "13:40", subject = "ПОПД", room = "24/1"),
    )),
))
private val days = listOf(monday, saturday, friday)

private fun query(subgroup: Subgroup, group: String = "ИСП-225а") = ScheduleQuery(days, group, subgroup)

class NextLessonTest {
    @Test fun ongoingLesson() {
        val state = query(Subgroup.FIRST).current(moscow("2026-10-23", "09:00"))
        assertEquals(1, (state as CurrentLessonState.Ongoing).lesson.lesson.pair)
    }

    @Test fun skipsOtherSubgroup() {
        // Subgroup 1 has nothing in pair 2, so after pair 1 the next is pair 3.
        val state = query(Subgroup.FIRST).current(moscow("2026-10-23", "10:05"))
        assertEquals(3, (state as CurrentLessonState.Upcoming).lesson.lesson.pair)
    }

    @Test fun breakBetweenPairsIsUpcoming() {
        val state = query(Subgroup.SECOND).current(moscow("2026-10-23", "10:00")) as CurrentLessonState.Upcoming
        assertEquals(2, state.lesson.lesson.pair)
        assertEquals(moscow("2026-10-23", "10:10"), state.lesson.start)
    }

    @Test fun finishedForToday() {
        assertEquals(CurrentLessonState.FinishedForToday, query(Subgroup.FIRST).current(moscow("2026-10-23", "13:40")))
    }

    @Test fun noLessonsOnSunday() {
        assertEquals(CurrentLessonState.NoLessonsToday, query(Subgroup.FIRST).current(moscow("2026-10-25", "09:00")))
    }

    @Test fun unknownGroupHasNoLessons() {
        assertEquals(CurrentLessonState.NoLessonsToday, query(Subgroup.UNSPECIFIED, "НЕТ-000").current(moscow("2026-10-23", "09:00")))
    }

    @Test fun otherSubgroupIsHidden() {
        assertEquals(listOf(1, 3), query(Subgroup.FIRST).lessons(friday).map { it.pair })
    }

    @Test fun unspecifiedSubgroupSeesEverything() {
        assertEquals(4, query(Subgroup.UNSPECIFIED).lessons(friday).size)
    }

    @Test fun todayUsesMoscowNotDeviceZone() {
        // 23:30 in Moscow on Friday is already Saturday in Vladivostok.
        val lateFriday = moscow("2026-10-23", "23:30")
        assertEquals(24, ZonedDateTime.ofInstant(lateFriday, ZoneId.of("Asia/Vladivostok")).dayOfMonth)
        assertEquals("2026-10-23", query(Subgroup.FIRST).day(lateFriday)?.date)
    }
}

class NextSchoolDayTest {
    @Test fun tomorrowWithLessons() {
        val next = query(Subgroup.SECOND).nextSchoolDay(moscow("2026-10-23", "18:00"))!!
        assertEquals("2026-10-24", next.day.date)
        assertTrue(next.isTomorrow)
        assertFalse(next.tomorrowIsFree)
    }

    @Test fun tomorrowFreeForSubgroupSkipsToNextDay() {
        // Saturday only has a subgroup-2 lesson; subgroup 1 is free.
        val next = query(Subgroup.FIRST).nextSchoolDay(moscow("2026-10-23", "18:00"))!!
        assertEquals("2026-10-26", next.day.date)
        assertFalse(next.isTomorrow)
        assertTrue(next.tomorrowIsFree)
        assertEquals(2, next.lessons.size)
    }

    @Test fun sundayLooksToMonday() {
        val next = query(Subgroup.FIRST).nextSchoolDay(moscow("2026-10-25", "12:00"))!!
        assertEquals("2026-10-26", next.day.date)
        assertTrue(next.isTomorrow)
    }

    @Test fun noFutureDays() {
        assertNull(query(Subgroup.FIRST).nextSchoolDay(moscow("2026-10-26", "08:00")))
    }

    @Test fun startsAtFollowsSubgroup() {
        assertEquals("11:10", query(Subgroup.SECOND).startsAt(saturday))
        assertNull(query(Subgroup.FIRST).startsAt(saturday))
    }
}

class LunchTest {
    private val day = Day("2026-10-23", building = 1, groups = listOf(
        GroupDay("ДО-324", emptyList(), listOf(
            Note(Note.Kind.LUNCH, "Обед 10:55-11:20", time = "10:55", endTime = "11:20", pair = 3, subgroup = 1),
            Note(Note.Kind.LUNCH, "Обед 10:55-11:20", time = "10:55", endTime = "11:20", pair = 5, subgroup = 2),
            Note(Note.Kind.LUNCH, "Обед 11:40-12:10", time = "11:40", endTime = "12:10", pair = 4, subgroup = 2),
            Note(Note.Kind.STARTS_AT, "Занятия начинаются с 11:10", time = "11:10"),
        )),
    ))

    @Test fun filtersBySubgroup() {
        assertEquals(listOf("10:55"), ScheduleQuery(listOf(day), "ДО-324", Subgroup.FIRST).lunches(day).map { it.time })
    }

    @Test fun deduplicatesAcrossSubgroups() {
        assertEquals(listOf("10:55", "11:40"), ScheduleQuery(listOf(day), "ДО-324", Subgroup.UNSPECIFIED).lunches(day).map { it.time })
    }
}

class FirstStartTest {
    @Test fun mixedDayUsesFirstInPersonClass() {
        // Saturday of ИСП-225ис: remote pairs 1–2, PE in person from 11:50.
        val lessons = listOf(
            Lesson(pair = 1, start = "09:00", subject = "ПОПД", isRemote = true, timeSource = "bells"),
            Lesson(pair = 2, start = "10:40", subject = "ПОПД", isRemote = true, timeSource = "bells"),
            Lesson(pair = 3, start = "11:50", subject = "Физ. культура", room = "СЗ/2", timeSource = "startsAt"),
        )
        assertEquals("11:50", ScheduleQuery.firstInPersonStart(lessons)?.start)
    }

    @Test fun allRemoteHasNoStart() {
        val lessons = listOf(
            Lesson(pair = 2, start = "10:10", subject = "ОСиС", isRemote = true),
            Lesson(pair = 1, start = "08:30", subject = "ОСиС", isRemote = true),
        )
        assertNull(ScheduleQuery.firstInPersonStart(lessons))
    }

    @Test fun regularDayUsesFirstClass() {
        val lessons = listOf(
            Lesson(pair = 3, start = "12:10", subject = "История", room = "16/1"),
            Lesson(pair = 2, start = "10:10", subject = "ПОПД", room = "24/1"),
        )
        assertEquals(2, ScheduleQuery.firstInPersonStart(lessons)?.pair)
    }
}

class BuildingTest {
    @Test fun zeroBuildingFallsBackToDay() {
        assertEquals(2, Lesson(pair = 1, building = 0, start = "08:30", subject = "X").building(2))
        assertEquals(1, Lesson(pair = 1, building = 1, start = "08:30", subject = "X").building(2))
    }

    @Test fun buildingComesFromLessons() {
        val day = Day("2026-10-24", building = 1, groups = listOf(GroupDay("ИСП-225ис", listOf(
            Lesson(pair = 1, building = 2, start = "09:00", subject = "ПОПД", isRemote = true),
            Lesson(pair = 3, building = 2, start = "11:50", subject = "Физ. культура", room = "СЗ/2"),
        ))))
        assertEquals(listOf(2), ScheduleQuery(listOf(day), "ИСП-225ис", Subgroup.UNSPECIFIED).buildings(day))
    }
}

class DecodingTest {
    @Test fun decodesServerPayload() {
        val json = """
            {"group":"ЭСС-225","parsedAt":"2026-10-23T12:10:49.316279998+03:00",
             "sourceModified":"2026-10-23T08:52:17Z",
             "days":[{"date":"2026-10-24","weekday":"суббота","building":1,"groups":[{"group":"ЭСС-225",
               "lessons":[{"pair":1,"building":2,"pairTo":6,"start":"08:30","end":"18:50","subject":"Экзамен","isRemote":false,"timeSource":"bells"}],
               "notes":[{"kind":"somethingNew","text":"?"}]}]}]}
        """.trimIndent()
        val r = Json.schedule(json)
        val group = r.days[0].groups[0]
        assertEquals("1–6", group.lessons[0].pairLabel)
        assertEquals(Note.Kind.OTHER, group.notes[0].kind)
        assertEquals(2, group.lessons[0].building)
        assertEquals(1_792_746_649_316L, r.parsedAt)
    }
}

class ValidationTest {
    private val groups = listOf(GroupInfo("ИСП-225а", 2, listOf(1, 2)))

    @Test fun requiresName() {
        val draft = ProfileDraft(fullName = "   ", group = "ИСП-225а")
        assertEquals(ProfileDraft.Result.Invalid(ProfileDraft.Problem.EMPTY_NAME), draft.validate(groups))
    }

    @Test fun groupMustComeFromServerList() {
        assertEquals(
            ProfileDraft.Result.Invalid(ProfileDraft.Problem.UNKNOWN_GROUP),
            ProfileDraft(fullName = "Иванов Иван", group = "ИСП-999").validate(groups),
        )
        assertEquals(
            ProfileDraft.Result.Valid(Profile("Иванов Иван", "ИСП-225а", 2, Subgroup.SECOND)),
            ProfileDraft(fullName = "Иванов Иван", group = "ИСП-225а", subgroup = Subgroup.SECOND).validate(groups),
        )
    }
}
