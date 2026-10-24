package ru.sked.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import kotlinx.coroutines.delay
import ru.sked.app.R
import ru.sked.app.core.CollegeClock
import ru.sked.app.core.Day
import ru.sked.app.core.Lesson
import ru.sked.app.core.Note
import ru.sked.app.core.Subgroup
import ru.sked.app.data.ApiError
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

// User-facing formatting of schedule data. The locale follows the app's
// resources (per-app language on Android 13+), so dates match the UI text.

@Composable
@ReadOnlyComposable
fun currentLocale(): Locale = LocalConfiguration.current.locales[0]

/** "08:30 – 10:00". */
fun timeRange(lesson: Lesson): String = lesson.end?.let { "${lesson.start} – $it" } ?: lesson.start

/** "каб. 15/2 · Петров С.И." or "дистант · Петров С.И.". */
@Composable
fun place(lesson: Lesson): String = listOfNotNull(
    when {
        lesson.isRemote -> stringResource(R.string.lesson_remote)
        lesson.room != null -> stringResource(R.string.lesson_room, lesson.room)
        else -> null
    },
    lesson.teacher,
).joinToString(" · ")

@Composable
fun lessonDescription(lesson: Lesson): String = listOf(
    stringResource(R.string.lesson_pair_number, lesson.pairLabel),
    lesson.subject,
    timeRange(lesson),
    place(lesson),
).filter { it.isNotEmpty() }.joinToString(", ")

/** "начнётся через 2 ч 13 мин"; rounds up so it never says "0 мин". */
@Composable
fun countdown(now: Instant, target: Instant): String {
    val minutes = maxOf(1L, (Duration.between(now, target).toSeconds() + 59) / 60)
    val text = when {
        minutes >= 24 * 60 -> stringResource(R.string.duration_days_hours, (minutes / 1440).toInt(), ((minutes % 1440) / 60).toInt())
        minutes >= 60 -> stringResource(R.string.duration_hours_minutes, (minutes / 60).toInt(), (minutes % 60).toInt())
        else -> stringResource(R.string.duration_minutes, minutes.toInt())
    }
    return stringResource(R.string.countdown_in, text)
}

@Composable
fun buildingLabel(number: Int): String = stringResource(R.string.building_short, number)

/** "корпус 1" or "корпуса 1, 2" when a day spans both. */
@Composable
fun buildingsLabel(numbers: List<Int>): String =
    if (numbers.size > 1) stringResource(R.string.building_many, numbers.joinToString(", "))
    else buildingLabel(numbers.firstOrNull() ?: 0)

/** "Обед 10:55–11:20", or "Обед с 10:55" when the PDF gives no end. */
@Composable
fun lunchLabel(note: Note): String {
    val time = note.time ?: return note.text
    return note.endTime?.let { stringResource(R.string.lunch_range, time, it) } ?: stringResource(R.string.lunch_from, time)
}

@Composable
fun subgroupName(subgroup: Subgroup): String =
    if (subgroup == Subgroup.UNSPECIFIED) stringResource(R.string.subgroup_unspecified)
    else stringResource(R.string.subgroup_badge, subgroup.number)

private fun String.capitalizedFirst(locale: Locale) = replaceFirstChar { it.titlecase(locale) }

/** "Пятница, 23 октября". */
@Composable
fun longDay(day: Day): String {
    val locale = currentLocale()
    val date = CollegeClock.date(day.date) ?: return day.date
    return date.format(DateTimeFormatter.ofPattern("EEEE, d MMMM", locale)).capitalizedFirst(locale)
}

/** "Пт, 23.10". */
@Composable
fun shortDay(day: Day): String {
    val locale = currentLocale()
    val date = CollegeClock.date(day.date) ?: return day.date
    return date.format(DateTimeFormatter.ofPattern("EE, dd.MM", locale)).capitalizedFirst(locale)
}

/** Chip label: short weekday and day number. */
@Composable
fun chipLabel(day: Day): Pair<String, String> {
    val locale = currentLocale()
    val date = CollegeClock.date(day.date) ?: return day.date to ""
    return date.format(DateTimeFormatter.ofPattern("EE", locale)).capitalizedFirst(locale) to date.dayOfMonth.toString()
}

/** "сегодня" / "завтра" relative to now, or null. */
@Composable
fun relativeDay(day: Day, now: Instant): String? {
    val today = now.atZone(CollegeClock.zone).toLocalDate()
    return when (day.date) {
        today.toString() -> stringResource(R.string.day_today)
        today.plusDays(1).toString() -> stringResource(R.string.day_tomorrow)
        else -> null
    }
}

/** "23 окт. 2026 г., 12:29" in the device zone. */
@Composable
fun dateTime(epochMillis: Long): String =
    Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault())
        .format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(currentLocale()))

@Composable
fun errorTitle(error: ApiError): String = when (error) {
    is ApiError.CannotConnect -> stringResource(R.string.error_cannot_connect, error.host)
    ApiError.TimedOut -> stringResource(R.string.error_timed_out)
    ApiError.Offline -> stringResource(R.string.error_offline)
    ApiError.NotLoadedYet -> stringResource(R.string.error_not_loaded_yet)
    is ApiError.Server -> error.serverMessage?.let { stringResource(R.string.error_server_message, error.status, it) }
        ?: stringResource(R.string.error_server, error.status)
    ApiError.BadResponse -> stringResource(R.string.error_bad_response)
}

@Composable
fun errorRecovery(error: ApiError): String = when (error) {
    is ApiError.CannotConnect -> stringResource(R.string.error_recovery_check_server)
    ApiError.Offline -> stringResource(R.string.error_recovery_offline)
    else -> stringResource(R.string.error_recovery_retry_later)
}

/** The current time, updated at the start of every minute (for countdowns). */
@Composable
fun rememberNow(): State<Instant> = produceState(Instant.now()) {
    while (true) {
        val untilNextMinute = 60_000 - System.currentTimeMillis() % 60_000
        delay(untilNextMinute)
        value = Instant.now()
    }
}
