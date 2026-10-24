package ru.sked.app.ui.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import ru.sked.app.R
import ru.sked.app.core.Profile
import ru.sked.app.core.Subgroup
import ru.sked.app.ui.AppViewModel
import ru.sked.app.ui.components.ErrorState
import ru.sked.app.ui.components.SectionHeader
import ru.sked.app.ui.dateTime
import ru.sked.app.ui.errorTitle
import ru.sked.app.ui.onboarding.GroupListState
import ru.sked.app.ui.onboarding.GroupPickerScreen
import ru.sked.app.ui.onboarding.SubgroupSelector
import ru.sked.app.ui.subgroupName

private enum class Page { MAIN, EDIT, GROUP }

@Composable
fun ProfileScreen(model: AppViewModel) {
    var page by rememberSaveable { mutableStateOf(Page.MAIN) }
    val profile = model.profile ?: return
    when (page) {
        Page.MAIN -> ProfileMain(model, profile, onEdit = { page = Page.EDIT })
        Page.EDIT -> ProfileEditor(model, profile, onGroup = { page = Page.GROUP }, onBack = { page = Page.MAIN })
        Page.GROUP -> GroupEditor(model, profile, onDone = { page = Page.EDIT })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileMain(model: AppViewModel, profile: Profile, onEdit: () -> Unit) {
    val scope = rememberCoroutineScope()

    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.tab_profile)) }) }) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            ProfileCard(profile, onEdit, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))

            SectionHeader(stringResource(R.string.profile_data))
            ListItem(
                headlineContent = { Text(stringResource(R.string.profile_data_updated)) },
                supportingContent = { Text(model.dataFetchedAt?.let { dateTime(it) } ?: stringResource(R.string.profile_never)) },
            )
            model.schedule?.let {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.profile_server_parsed)) },
                    supportingContent = { Text(dateTime(it.parsedAt)) },
                )
            }
            model.staleReason?.let {
                ListItem(
                    headlineContent = { Text(errorTitle(it), color = MaterialTheme.colorScheme.error) },
                )
            }
            ListItem(
                headlineContent = { Text(stringResource(R.string.profile_refresh_now), color = MaterialTheme.colorScheme.primary) },
                trailingContent = { if (model.isRefreshing) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp) },
                modifier = Modifier.clickable(enabled = !model.isRefreshing) { scope.launch { model.refresh() } },
            )

            SectionHeader(stringResource(R.string.profile_about))
            ListItem(
                headlineContent = { Text(stringResource(R.string.profile_version)) },
                supportingContent = { Text(appVersion()) },
            )

        }
    }
}

/** The user card: initials, name, "group · course" and the subgroup as plain text. */
@Composable
private fun ProfileCard(profile: Profile, onEdit: () -> Unit, modifier: Modifier = Modifier) {
    val hint = stringResource(R.string.profile_edit_hint)
    ElevatedCard(
        onClick = onEdit,
        modifier = modifier.fillMaxWidth().semantics { onClick(label = hint) { onEdit(); true } },
    ) {
        ListItem(
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
            leadingContent = {
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary, modifier = Modifier.size(56.dp)) {
                    Box(contentAlignment = Alignment.Center) {
                        Text(initials(profile.fullName), style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onPrimary)
                    }
                }
            },
            headlineContent = { Text(profile.fullName, style = MaterialTheme.typography.titleLarge) },
            supportingContent = {
                Column {
                    Text("${profile.group} · ${stringResource(R.string.course_label, profile.course)}")
                    if (profile.subgroup != Subgroup.UNSPECIFIED) Text(subgroupName(profile.subgroup))
                }
            },
            trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null) },
            modifier = Modifier.padding(vertical = 8.dp),
        )
    }
}

/** "Фамилия Имя Отчество" → "ИФ"; a single word → its first letter. */
private fun initials(fullName: String): String {
    val words = fullName.split(" ").filter { it.isNotBlank() }
    val letters = if (words.size > 1) listOf(words[1], words[0]) else words.take(1)
    return letters.mapNotNull { it.firstOrNull()?.uppercaseChar() }.joinToString("")
}

@Composable
private fun appVersion(): String {
    val context = LocalContext.current
    val info = remember { context.packageManager.getPackageInfo(context.packageName, 0) }
    return "${info.versionName} (${info.longVersionCode})"
}

/** Name, group, subgroup and resetting the profile, behind the profile card. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileEditor(model: AppViewModel, profile: Profile, onGroup: () -> Unit, onBack: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(profile.fullName) }
    var confirmsReset by remember { mutableStateOf(false) }
    val currentName by rememberUpdatedState(name)

    // An empty name is not saved; the previous one stays.
    fun saveName() {
        val trimmed = currentName.trim()
        val current = model.profile ?: return
        if (trimmed.isNotEmpty() && trimmed != current.fullName) model.save(current.copy(fullName = trimmed))
    }
    DisposableEffect(Unit) { onDispose { saveName() } }
    BackHandler(onBack = onBack)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.profile_edit)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.action_back))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.profile_full_name)) },
                supportingText = { Text(stringResource(R.string.onboarding_name_footer)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedCard(Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.profile_group)) },
                    supportingContent = { Text("${profile.group} · ${stringResource(R.string.course_label, profile.course)}") },
                    trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null) },
                    modifier = Modifier.clickable(onClick = onGroup),
                )
            }
            SubgroupSelector(profile.subgroup) { subgroup ->
                model.profile?.let { if (it.subgroup != subgroup) model.save(it.copy(subgroup = subgroup)) }
            }
            TextButton(onClick = { confirmsReset = true }, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.profile_reset), color = MaterialTheme.colorScheme.error)
            }
        }
    }

    if (confirmsReset) {
        AlertDialog(
            onDismissRequest = { confirmsReset = false },
            title = { Text(stringResource(R.string.profile_reset_confirm)) },
            text = { Text(stringResource(R.string.profile_reset_message)) },
            confirmButton = {
                TextButton(onClick = { confirmsReset = false; model.resetProfile() }) {
                    Text(stringResource(R.string.profile_reset), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmsReset = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}

/** Picks another group from the server list. */
@Composable
private fun GroupEditor(model: AppViewModel, profile: Profile, onDone: () -> Unit) {
    val list = remember { GroupListState() }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { list.load(model) }
    BackHandler(onBack = onDone)

    when (val state = list.state) {
        GroupListState.State.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        is GroupListState.State.Failed -> ErrorState(state.error, onRetry = { scope.launch { list.load(model) } })
        is GroupListState.State.Loaded -> GroupPickerScreen(
            groups = state.groups,
            selection = profile.group,
            onPick = { name ->
                state.groups.firstOrNull { it.name == name }?.let { info ->
                    model.profile?.let { model.save(it.copy(group = info.name, course = info.course)) }
                }
                onDone()
            },
            onBack = onDone,
        )
    }
}
