package ru.sked.app.core

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The college works on Moscow time; "today" is computed in Europe/Moscow so a
 * device in another zone does not shift the schedule.
 */
object CollegeClock {
    val zone: ZoneId = ZoneId.of("Europe/Moscow")

    /** "YYYY-MM-DD" of [instant] in Moscow. */
    fun dayString(instant: Instant): String = instant.atZone(zone).toLocalDate().toString()

    fun date(day: String): LocalDate? = runCatching { LocalDate.parse(day) }.getOrNull()

    /** A Moscow wall-clock time on a given day. */
    fun instant(day: String, time: String): Instant? {
        val date = date(day) ?: return null
        val parts = time.split(":").mapNotNull { it.toIntOrNull() }
        if (parts.size != 2) return null
        return runCatching { ZonedDateTime.of(date, LocalTime.of(parts[0], parts[1]), zone).toInstant() }.getOrNull()
    }
}

/** A lesson placed on the timeline. */
data class ScheduledLesson(val lesson: Lesson, val day: Day, val start: Instant, val end: Instant)

/** What the "next class" card shows. */
sealed interface CurrentLessonState {
    data class Ongoing(val lesson: ScheduledLesson) : CurrentLessonState
    data class Upcoming(val lesson: ScheduledLesson) : CurrentLessonState
    /** Today had lessons and all of them are over. */
    data object FinishedForToday : CurrentLessonState
    /** No lessons today at all (weekend or empty day). */
    data object NoLessonsToday : CurrentLessonState
}

/** Answers schedule questions for one group and subgroup. */
class ScheduleQuery(days: List<Day>, val group: String, val subgroup: Subgroup) {
    val days: List<Day> = days.sortedBy { it.date }

    fun groupDay(day: Day): GroupDay? = day.groups.firstOrNull { it.group == group }

    /** Whole-group lessons plus the user's subgroup; everything with no subgroup chosen. */
    fun lessons(day: Day): List<Lesson> =
        (groupDay(day)?.lessons ?: emptyList())
            .filter(::isVisible)
            .sortedWith(compareBy({ it.pair }, { it.subgroup ?: 0 }))

    fun isVisible(lesson: Lesson): Boolean =
        subgroup == Subgroup.UNSPECIFIED || lesson.subgroup == null || lesson.subgroup == subgroup.number

    /** Buildings the user goes to on a day, from the lessons themselves. */
    fun buildings(day: Day): List<Int> = buildings(lessons(day), day.building)

    /**
     * "Classes start at …" («Занятия начинаются с …») for the user's subgroup,
     * only when it says something the lessons don't: hidden when the first
     * in-person class already starts at that time (the server aligns derived
     * Saturday times with it) or when there is no in-person class that day.
     */
    fun startsAt(day: Day): String? {
        val time = groupDay(day)?.notes?.firstOrNull { it.kind == Note.Kind.STARTS_AT && noteIsVisible(it) }?.time
            ?: return null
        val firstInPerson = lessons(day).filter { !it.isRemote && it.start.isNotEmpty() }.minOfOrNull { it.start }
            ?: return null
        return time.takeIf { it != firstInPerson }
    }

    /**
     * Lunch breaks for the user's subgroup, without duplicates (the PDF often
     * repeats the same lunch in both subgroup columns), earliest first.
     */
    fun lunches(day: Day): List<Note> =
        (groupDay(day)?.notes ?: emptyList())
            .filter { it.kind == Note.Kind.LUNCH && it.time != null && noteIsVisible(it) }
            .distinctBy { "${it.time}-${it.endTime}" }
            .sortedBy { it.time }

    private fun noteIsVisible(note: Note): Boolean =
        subgroup == Subgroup.UNSPECIFIED || note.subgroup == null || note.subgroup == subgroup.number

    fun day(instant: Instant): Day? {
        val key = CollegeClock.dayString(instant)
        return days.firstOrNull { it.date == key }
    }

    /** Days from today on, as far as the PDF goes. */
    fun upcomingDays(now: Instant): List<Day> {
        val today = CollegeClock.dayString(now)
        return days.filter { it.date >= today }
    }

    fun scheduled(lesson: Lesson, day: Day): ScheduledLesson? {
        val start = CollegeClock.instant(day.date, lesson.start) ?: return null
        val end = lesson.end?.let { CollegeClock.instant(day.date, it) } ?: start.plus(DEFAULT_LENGTH)
        return ScheduledLesson(lesson, day, start, end)
    }

    fun current(now: Instant): CurrentLessonState {
        val today = day(now) ?: return CurrentLessonState.NoLessonsToday
        val timeline = lessons(today).mapNotNull { scheduled(it, today) }.sortedBy { it.start }
        if (timeline.isEmpty()) return CurrentLessonState.NoLessonsToday
        timeline.firstOrNull { it.start <= now && now < it.end }?.let { return CurrentLessonState.Ongoing(it) }
        timeline.firstOrNull { it.start > now }?.let { return CurrentLessonState.Upcoming(it) }
        return CurrentLessonState.FinishedForToday
    }

    /** The next upcoming lesson after [now], today only. */
    fun nextLessonToday(now: Instant): ScheduledLesson? {
        val today = day(now) ?: return null
        return lessons(today).mapNotNull { scheduled(it, today) }.filter { it.start > now }.minByOrNull { it.start }
    }

    companion object {
        /** A lesson without an end time lasts a standard pair. */
        val DEFAULT_LENGTH: Duration = Duration.ofMinutes(90)

        fun buildings(lessons: List<Lesson>, fallback: Int): List<Int> {
            val set = lessons.map { it.building(fallback) }.toSortedSet()
            return if (set.isEmpty()) listOf(fallback) else set.toList()
        }
    }
}
