package ru.sked.app.core

enum class Subgroup(val number: Int) {
    UNSPECIFIED(0), FIRST(1), SECOND(2);

    companion object {
        fun of(number: Int): Subgroup = entries.firstOrNull { it.number == number } ?: UNSPECIFIED
    }
}

/**
 * The student's profile. Stored only on the device. There is no building:
 * groups move between buildings from day to day, so it comes with each pair.
 */
data class Profile(
    val fullName: String,
    val group: String,
    /** Derived from the group number, e.g. "ИСП-324а" → 3. */
    val course: Int,
    val subgroup: Subgroup,
)

/** Onboarding input before it becomes a [Profile]. */
data class ProfileDraft(
    val fullName: String = "",
    val group: String? = null,
    val subgroup: Subgroup = Subgroup.UNSPECIFIED,
) {
    enum class Problem { EMPTY_NAME, NO_GROUP, UNKNOWN_GROUP }

    sealed interface Result {
        data class Valid(val profile: Profile) : Result
        data class Invalid(val problem: Problem) : Result
    }

    /** Validates against the group list the server returned. */
    fun validate(availableGroups: List<GroupInfo>): Result {
        val name = fullName.trim()
        if (name.isEmpty()) return Result.Invalid(Problem.EMPTY_NAME)
        val group = group ?: return Result.Invalid(Problem.NO_GROUP)
        val info = availableGroups.firstOrNull { it.name == group }
            ?: return Result.Invalid(Problem.UNKNOWN_GROUP)
        return Result.Valid(Profile(name, group, info.course, subgroup))
    }
}
