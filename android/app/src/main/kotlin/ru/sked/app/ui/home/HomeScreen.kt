package ru.sked.app.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import ru.sked.app.R
import ru.sked.app.core.CurrentLessonState
import ru.sked.app.core.Lesson
import ru.sked.app.core.ScheduleQuery
import ru.sked.app.core.ScheduledLesson
import ru.sked.app.ui.AppViewModel
import ru.sked.app.ui.buildingLabel
import ru.sked.app.ui.components.ErrorState
import ru.sked.app.ui.components.StaleDataBanner
import ru.sked.app.ui.countdown
import ru.sked.app.ui.dateTime
import ru.sked.app.ui.rememberNow
import ru.sked.app.ui.subgroupName
import ru.sked.app.core.Subgroup
import java.time.Instant

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(model: AppViewModel) {
    val scope = rememberCoroutineScope()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val name = model.profile?.fullName?.split(" ")?.filter { it.isNotBlank() }
    // "Фамилия Имя Отчество" → greet by the given name.
    val firstName = name?.getOrNull(1) ?: name?.firstOrNull()
    val title = firstName?.let { stringResource(R.string.home_greeting, it) } ?: stringResource(R.string.tab_home)

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = { LargeTopAppBar(title = { Text(title) }, scrollBehavior = scrollBehavior) },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = model.isRefreshing,
            onRefresh = { scope.launch { model.refresh() } },
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            when (val state = model.scheduleState) {
                AppViewModel.ScheduleState.Idle, AppViewModel.ScheduleState.Loading -> HomeSkeleton()
                is AppViewModel.ScheduleState.Failed -> ErrorState(state.error, onRetry = { model.refreshAsync() })
                is AppViewModel.ScheduleState.Loaded -> model.query?.let { HomeCards(model, it) }
            }
        }
    }
}

@Composable
private fun HomeCards(model: AppViewModel, query: ScheduleQuery) {
    val now by rememberNow()
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        model.staleReason?.let { reason ->
            item {
                StaleDataBanner(
                    title = model.dataFetchedAt?.let { stringResource(R.string.stale_title, dateTime(it)) },
                    reason = reason,
                    onRetry = { model.refreshAsync() },
                )
            }
        }
        item { CurrentLessonCard(query.current(now), now) }
    }
}

@Composable
private fun CurrentLessonCard(state: CurrentLessonState, now: Instant) {
    when (state) {
        is CurrentLessonState.Ongoing -> LessonCard(state.lesson, stringResource(R.string.home_ongoing), ongoing = true)
        is CurrentLessonState.Upcoming -> LessonCard(state.lesson, countdown(now, state.lesson.start), ongoing = false)
        CurrentLessonState.FinishedForToday -> MessageCard(stringResource(R.string.home_finished))
        CurrentLessonState.NoLessonsToday -> MessageCard(stringResource(R.string.home_no_lessons_today))
    }
}

@Composable
private fun LessonCard(scheduled: ScheduledLesson, status: String, ongoing: Boolean) {
    val lesson = scheduled.lesson
    val headline = headline(lesson, lesson.building(scheduled.day.building))
    val label = stringResource(R.string.home_next_lesson)
    val subgroup = lesson.subgroup?.let { subgroupName(Subgroup.of(it)) }
    val description = listOfNotNull(label, headline, lesson.teacher, subgroup, status).joinToString(", ")
    ElevatedCard(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = description },
        colors = if (ongoing) CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
        else CardDefaults.elevatedCardColors(),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label.uppercase(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(headline, style = MaterialTheme.typography.titleLarge)
            lesson.teacher?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            subgroup?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            Spacer(Modifier.height(4.dp))
            Text(status, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
        }
    }
}

/** "2 пара · ОБиЗР · 14:30 · корпус 2, каб. 15/2". */
@Composable
private fun headline(lesson: Lesson, building: Int): String = listOf(
    stringResource(R.string.lesson_pair_number, lesson.pairLabel),
    lesson.subject,
    lesson.start,
    when {
        lesson.isRemote -> stringResource(R.string.lesson_remote)
        lesson.room != null -> stringResource(R.string.home_building_room, building, lesson.room)
        else -> buildingLabel(building)
    },
).joinToString(" · ")

@Composable
private fun MessageCard(text: String) {
    ElevatedCard(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}) {
        Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(20.dp))
    }
}

@Composable
private fun HomeSkeleton() {
    val placeholder = MaterialTheme.colorScheme.surfaceVariant
    val loading = stringResource(R.string.a11y_loading)
    Column(
        Modifier.fillMaxSize().padding(16.dp).semantics { contentDescription = loading },
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        repeat(2) {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Bar(placeholder, 0.35f, 12)
                    Bar(placeholder, 0.9f, 22)
                    Bar(placeholder, 0.6f, 16)
                }
            }
        }
    }
}

@Composable
private fun Bar(color: Color, fraction: Float, heightDp: Int) {
    Box(Modifier.fillMaxWidth(fraction).height(heightDp.dp).background(color, RoundedCornerShape(6.dp)))
}
