package ru.sked.app.core

/** A pair (or a run of pairs merged into one cell) as served by `GET /schedule`. */
data class Lesson(
    val pair: Int,
    /** Building of this pair; a group may change buildings between days. */
    val building: Int? = null,
    /** Last pair of a cell that spans several pairs, e.g. an exam. */
    val pairTo: Int? = null,
    /** "HH:mm", Europe/Moscow. */
    val start: String,
    val end: String? = null,
    val subject: String,
    val teacher: String? = null,
    val room: String? = null,
    val isRemote: Boolean = false,
    /** `null` means the whole group. */
    val subgroup: Int? = null,
    val note: String? = null,
    /** Set when the PDF had no time for this pair and the server derived it. */
    val timeSource: String? = null,
) {
    val id: String get() = "$pair-${subgroup ?: 0}-$subject"

    /** "2" or "1–6" for merged cells. */
    val pairLabel: String get() = if (pairTo != null && pairTo != pair) "$pair–$pairTo" else "$pair"

    /** The lesson's building, or [fallback] when the server sent none (or 0). */
    fun building(fallback: Int): Int = building?.takeIf { it > 0 } ?: fallback
}

data class Note(
    val kind: Kind,
    val text: String,
    val time: String? = null,
    val endTime: String? = null,
    val pair: Int? = null,
    val subgroup: Int? = null,
) {
    enum class Kind { STARTS_AT, LUNCH, OTHER }
}

data class GroupDay(
    val group: String,
    val lessons: List<Lesson>,
    val notes: List<Note> = emptyList(),
)

data class Day(
    /** "YYYY-MM-DD". */
    val date: String,
    val weekday: String? = null,
    val building: Int,
    val groups: List<GroupDay>,
)

data class ScheduleResponse(
    val group: String? = null,
    /** Epoch milliseconds. */
    val parsedAt: Long,
    val days: List<Day>,
)

data class GroupInfo(
    val name: String,
    val course: Int,
    /** Buildings the group has classes in. */
    val buildings: List<Int> = emptyList(),
)
