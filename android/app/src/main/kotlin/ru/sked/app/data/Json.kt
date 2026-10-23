package ru.sked.app.data

import org.json.JSONArray
import org.json.JSONObject
import ru.sked.app.core.Day
import ru.sked.app.core.GroupDay
import ru.sked.app.core.GroupInfo
import ru.sked.app.core.Lesson
import ru.sked.app.core.Note
import ru.sked.app.core.ScheduleResponse
import java.time.OffsetDateTime

/** Decoding of server payloads (see docs/ARCHITECTURE.md, "API"). */
object Json {
    fun schedule(text: String): ScheduleResponse {
        val o = JSONObject(text)
        return ScheduleResponse(
            group = o.optStringOrNull("group"),
            parsedAt = OffsetDateTime.parse(o.getString("parsedAt")).toInstant().toEpochMilli(),
            days = o.getJSONArray("days").objects().map(::day),
        )
    }

    fun groups(text: String): List<GroupInfo> =
        JSONObject(text).getJSONArray("groups").objects().map { g ->
            GroupInfo(
                name = g.getString("name"),
                course = g.optInt("course"),
                buildings = g.optJSONArray("buildings")?.let { a -> (0 until a.length()).map(a::getInt) } ?: emptyList(),
            )
        }

    /** The `{"error": "..."}` body of a failed request, if any. */
    fun errorMessage(text: String): String? = runCatching { JSONObject(text).optStringOrNull("error") }.getOrNull()

    private fun day(o: JSONObject) = Day(
        date = o.getString("date"),
        weekday = o.optStringOrNull("weekday"),
        building = o.optInt("building"),
        groups = o.getJSONArray("groups").objects().map { g ->
            GroupDay(
                group = g.getString("group"),
                lessons = g.getJSONArray("lessons").objects().map(::lesson),
                notes = g.optJSONArray("notes")?.objects()?.map(::note) ?: emptyList(),
            )
        },
    )

    private fun lesson(o: JSONObject) = Lesson(
        pair = o.getInt("pair"),
        building = o.optIntOrNull("building"),
        pairTo = o.optIntOrNull("pairTo"),
        start = o.optString("start"),
        end = o.optStringOrNull("end"),
        subject = o.getString("subject"),
        teacher = o.optStringOrNull("teacher"),
        room = o.optStringOrNull("room"),
        isRemote = o.optBoolean("isRemote"),
        subgroup = o.optIntOrNull("subgroup"),
        note = o.optStringOrNull("note"),
        timeSource = o.optStringOrNull("timeSource"),
    )

    private fun note(o: JSONObject) = Note(
        // Unknown kinds from a newer server degrade to OTHER.
        kind = when (o.optString("kind")) {
            "startsAt" -> Note.Kind.STARTS_AT
            "lunch" -> Note.Kind.LUNCH
            else -> Note.Kind.OTHER
        },
        text = o.optString("text"),
        time = o.optStringOrNull("time"),
        endTime = o.optStringOrNull("endTime"),
        pair = o.optIntOrNull("pair"),
        subgroup = o.optIntOrNull("subgroup"),
    )

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map(::getJSONObject)

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) getString(key) else null

    private fun JSONObject.optIntOrNull(key: String): Int? =
        if (has(key) && !isNull(key)) getInt(key) else null
}
