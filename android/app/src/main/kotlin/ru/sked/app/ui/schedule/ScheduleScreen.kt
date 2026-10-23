package ru.sked.app.ui.schedule

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import kotlinx.coroutines.launch
import ru.sked.app.R
import ru.sked.app.core.CollegeClock
import ru.sked.app.core.Day
import ru.sked.app.core.ScheduleQuery
import ru.sked.app.ui.AppViewModel
import ru.sked.app.ui.buildingsLabel
import ru.sked.app.ui.chipLabel
import ru.sked.app.ui.components.CompactLessonRow
import ru.sked.app.ui.components.DayNotes
import ru.sked.app.ui.components.EmptyState
import ru.sked.app.ui.components.ErrorState
import ru.sked.app.ui.components.LessonCard
import ru.sked.app.ui.components.StaleDataBanner
import ru.sked.app.ui.countdown
import ru.sked.app.ui.dateTime
import ru.sked.app.ui.longDay
import ru.sked.app.ui.relativeDay
import ru.sked.app.ui.rememberNow
import ru.sked.app.ui.shortDay
import java.time.Instant

private enum class Mode { DAY, WEEK }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(model: AppViewModel) {
    var mode by rememberSaveable { mutableStateOf(Mode.DAY) }
    var selectedDate by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.tab_schedule)) }) }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            val modes = listOf(Mode.DAY to R.string.schedule_day, Mode.WEEK to R.string.schedule_week)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                modes.forEachIndexed { index, (value, label) ->
                    SegmentedButton(
                        selected = mode == value,
                        onClick = { mode = value },
                        shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                    ) { Text(stringResource(label)) }
                }
            }

            PullToRefreshBox(
                isRefreshing = model.isRefreshing,
                onRefresh = { scope.launch { model.refresh() } },
                modifier = Modifier.fillMaxSize(),
            ) {
                when (val state = model.scheduleState) {
                    AppViewModel.ScheduleState.Idle, AppViewModel.ScheduleState.Loading ->
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    is AppViewModel.ScheduleState.Failed -> ErrorState(state.error, onRetry = { model.refreshAsync() })
                    is AppViewModel.ScheduleState.Loaded -> model.query?.let { query ->
                        val now by rememberNow()
                        val days = query.upcomingDays(now)
                        val stale: @Composable () -> Unit = {
                            model.staleReason?.let { reason ->
                                StaleDataBanner(
                                    title = model.dataFetchedAt?.let { stringResource(R.string.stale_title, dateTime(it)) },
                                    reason = reason,
                                    onRetry = { model.refreshAsync() },
                                )
                            }
                        }
                        when {
                            days.isEmpty() -> NoDays()
                            mode == Mode.DAY -> DaySchedule(query, days, selectedDate, { selectedDate = it }, now, stale)
                            else -> WeekSchedule(query, days, now, stale)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NoDays() {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(stringResource(R.string.schedule_no_days), style = MaterialTheme.typography.titleMedium)
        Text(
            stringResource(R.string.schedule_no_days_hint),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun DaySchedule(
    query: ScheduleQuery,
    days: List<Day>,
    selectedDate: String?,
    onSelect: (String) -> Unit,
    now: Instant,
    stale: @Composable () -> Unit,
) {
    val day = days.firstOrNull { it.date == selectedDate } ?: days.first()
    val lessons = query.lessons(day)
    // "Пятница, 23 октября · сегодня · корпус 2".
    val title = listOfNotNull(longDay(day), relativeDay(day, now), buildingsLabel(query.buildings(day))).joinToString(" · ")

    LazyColumn(contentPadding = PaddingValues(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
        item { Column(Modifier.padding(horizontal = 16.dp)) { stale() } }
        item {
            LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(days, key = { it.date }) { chipDay ->
                    val (weekday, number) = chipLabel(chipDay)
                    val description = listOfNotNull(longDay(chipDay), relativeDay(chipDay, now)).joinToString(", ")
                    FilterChip(
                        selected = chipDay.date == day.date,
                        onClick = { onSelect(chipDay.date) },
                        label = {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(vertical = 6.dp)) {
                                Text(weekday, style = MaterialTheme.typography.labelSmall)
                                Text(number, style = MaterialTheme.typography.titleMedium)
                            }
                        },
                        modifier = Modifier.semantics { contentDescription = description },
                    )
                }
            }
        }
        item {
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(horizontal = 16.dp).semantics { heading() },
            )
        }
        if (day.date == CollegeClock.dayString(now)) {
            query.nextLessonToday(now)?.let { next ->
                item {
                    Card(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp).semantics(mergeDescendants = true) {},
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
                    ) {
                        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(painterResource(R.drawable.ic_schedule), contentDescription = null)
                            Text(
                                listOf(
                                    stringResource(R.string.schedule_next),
                                    stringResource(R.string.lesson_pair_number, next.lesson.pairLabel),
                                    countdown(now, next.start),
                                ).joinToString(" · "),
                                style = MaterialTheme.typography.titleSmall,
                            )
                        }
                    }
                }
            }
        }
        item {
            Column(Modifier.padding(horizontal = 16.dp)) {
                DayNotes(query.startsAt(day), query.lunches(day))
            }
        }
        if (lessons.isEmpty()) {
            item { EmptyState(stringResource(R.string.schedule_empty), R.drawable.ic_coffee) }
        } else {
            items(lessons, key = { it.id }) { lesson ->
                LessonCard(lesson, Modifier.padding(horizontal = 16.dp))
            }
        }
    }
}

@Composable
private fun WeekSchedule(query: ScheduleQuery, days: List<Day>, now: Instant, stale: @Composable () -> Unit) {
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
        item { stale() }
        items(days, key = { it.date }) { day ->
            val lessons = query.lessons(day)
            // "Пт, 23.10 · сегодня · корпус 2".
            val header = listOfNotNull(shortDay(day), relativeDay(day, now), buildingsLabel(query.buildings(day))).joinToString(" · ")
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(header, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                    DayNotes(query.startsAt(day), query.lunches(day), compact = true)
                    if (lessons.isEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(painterResource(R.drawable.ic_coffee), contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(stringResource(R.string.schedule_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    } else {
                        lessons.forEach { CompactLessonRow(it) }
                    }
                }
            }
        }
    }
}
