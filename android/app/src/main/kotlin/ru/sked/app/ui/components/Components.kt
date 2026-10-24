package ru.sked.app.ui.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import ru.sked.app.R
import ru.sked.app.core.Lesson
import ru.sked.app.core.Note
import ru.sked.app.data.ApiError
import ru.sked.app.ui.errorRecovery
import ru.sked.app.ui.errorTitle
import ru.sked.app.ui.lessonDescription
import ru.sked.app.ui.lunchLabel
import ru.sked.app.ui.place
import ru.sked.app.ui.timeRange

/** Title, message and Retry in one start-aligned column. */
@Composable
fun ErrorNotice(title: String?, message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            title?.let { Text(it, style = MaterialTheme.typography.titleSmall) }
            Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        FilledTonalButton(onClick = onRetry) { Text(stringResource(R.string.action_retry)) }
    }
}

/** "Показаны данные от …" when the network failed and the cache is shown. */
@Composable
fun StaleDataBanner(title: String?, reason: ApiError, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Card(
        modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
    ) {
        ErrorNotice(title, errorTitle(reason), onRetry, Modifier.padding(16.dp))
    }
}

/** Full-screen error when there is nothing cached to show. */
@Composable
fun ErrorState(error: ApiError, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(errorTitle(error), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            errorRecovery(error),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        Button(onClick = onRetry) { Text(stringResource(R.string.action_retry)) }
    }
}

/** Text for empty states such as "Пар нет". */
@Composable
fun EmptyState(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = modifier.fillMaxWidth().padding(vertical = 48.dp),
    )
}

/** The pair number in a tonal circle, centred against the row. */
@Composable
fun PairNumber(label: String, compact: Boolean = false) {
    val size = if (compact) 32.dp else 44.dp
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.primaryContainer,
        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        modifier = Modifier.defaultMinSize(minWidth = size, minHeight = size),
    ) {
        Box(Modifier.defaultMinSize(minWidth = size, minHeight = size).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
            Text(
                label,
                style = if (compact) MaterialTheme.typography.labelLarge else MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

/** One lesson in the day list: subject, then time, then place. */
@Composable
fun LessonCard(lesson: Lesson, modifier: Modifier = Modifier) {
    val description = lessonDescription(lesson)
    Card(modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = description }) {
        Row(
            Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            PairNumber(lesson.pairLabel)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(lesson.subject, style = MaterialTheme.typography.titleMedium)
                Text(timeRange(lesson), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(place(lesson), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                lesson.note?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** Compact row for the week view: numbered circle, then subject, time range and place. */
@Composable
fun CompactLessonRow(lesson: Lesson) {
    val description = lessonDescription(lesson)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).clearAndSetSemantics { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PairNumber(lesson.pairLabel, compact = true)
        Column {
            Text(lesson.subject, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(timeRange(lesson), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(place(lesson), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** "Занятия начинаются с …" and lunch breaks shown under a day's header. */
@Composable
fun DayNotes(startsAt: String?, lunches: List<Note>, compact: Boolean = false) {
    if (startsAt == null && lunches.isEmpty()) return
    val style = if (compact) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        startsAt?.let { NoteLine(R.drawable.ic_alarm, stringResource(R.string.home_starts_at, it), style) }
        lunches.forEach { NoteLine(R.drawable.ic_restaurant, lunchLabel(it), style) }
    }
}

@Composable
private fun NoteLine(@DrawableRes icon: Int, text: String, style: androidx.compose.ui.text.TextStyle) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(painterResource(icon), contentDescription = null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, style = style, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Material settings-style section label. */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 8.dp).semantics { heading() },
    )
}
