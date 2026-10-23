package ru.sked.app.data

import android.content.Context
import ru.sked.app.core.Profile
import ru.sked.app.core.ScheduleResponse
import ru.sked.app.core.Subgroup
import java.io.File
import java.net.URLEncoder

/** The profile, stored only on the device. */
class ProfileStore(context: Context) {
    private val prefs = context.getSharedPreferences("profile", Context.MODE_PRIVATE)

    fun load(): Profile? {
        val name = prefs.getString(NAME, null) ?: return null
        val group = prefs.getString(GROUP, null) ?: return null
        return Profile(name, group, prefs.getInt(COURSE, 0), Subgroup.of(prefs.getInt(SUBGROUP, 0)))
    }

    fun save(profile: Profile) {
        prefs.edit()
            .putString(NAME, profile.fullName)
            .putString(GROUP, profile.group)
            .putInt(COURSE, profile.course)
            .putInt(SUBGROUP, profile.subgroup.number)
            .apply()
    }

    fun clear() = prefs.edit().clear().apply()

    private companion object {
        const val NAME = "fullName"
        const val GROUP = "group"
        const val COURSE = "course"
        const val SUBGROUP = "subgroup"
    }
}

/** Last successful `/schedule` response per group, for offline use. */
class ScheduleCache(context: Context) {
    private val directory = File(context.filesDir, "schedule-cache")

    fun load(group: String): Pair<ScheduleResponse, Long>? {
        val file = file(group)
        if (!file.exists()) return null
        return runCatching { Json.schedule(file.readText()) to file.lastModified() }.getOrNull()
    }

    fun save(body: String, group: String) {
        runCatching {
            directory.mkdirs()
            // Write then rename so a crash never leaves a torn file.
            val tmp = File(directory, "${file(group).name}.tmp")
            tmp.writeText(body)
            tmp.renameTo(file(group))
        }
    }

    fun clear() {
        directory.deleteRecursively()
    }

    // Group names are Cyrillic with hyphens; encode for a safe file name.
    private fun file(group: String) = File(directory, URLEncoder.encode(group, "UTF-8") + ".json")
}
