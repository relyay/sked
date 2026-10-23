package ru.sked.app.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import ru.sked.app.R
import ru.sked.app.core.GroupInfo
import ru.sked.app.core.ProfileDraft
import ru.sked.app.core.Subgroup
import ru.sked.app.data.ApiError
import ru.sked.app.ui.AppViewModel
import ru.sked.app.ui.components.ErrorNotice
import ru.sked.app.ui.errorRecovery
import ru.sked.app.ui.errorTitle
import ru.sked.app.ui.subgroupName

/** The group list from the server, shared by onboarding and the profile. */
class GroupListState {
    sealed interface State {
        data object Loading : State
        data class Loaded(val groups: List<GroupInfo>) : State
        data class Failed(val error: ApiError) : State
    }

    var state by mutableStateOf<State>(State.Loading)
        private set

    val groups: List<GroupInfo> get() = (state as? State.Loaded)?.groups ?: emptyList()

    suspend fun load(model: AppViewModel) {
        state = State.Loading
        state = model.loadGroups().fold({ State.Loaded(it) }, { State.Failed(it as ApiError) })
    }
}

/** First launch: full name → group → subgroup on a single screen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingScreen(model: AppViewModel) {
    var name by rememberSaveable { mutableStateOf("") }
    var group by rememberSaveable { mutableStateOf<String?>(null) }
    var subgroup by rememberSaveable { mutableIntStateOf(Subgroup.UNSPECIFIED.number) }
    var attemptedSave by rememberSaveable { mutableStateOf(false) }
    var pickingGroup by rememberSaveable { mutableStateOf(false) }
    val groupList = remember { GroupListState() }
    val scope = rememberCoroutineScope()
    val nameFocus = remember { FocusRequester() }

    LaunchedEffect(Unit) { groupList.load(model) }

    if (pickingGroup) {
        GroupPickerScreen(groupList.groups, group, onPick = { group = it; pickingGroup = false }, onBack = { pickingGroup = false })
        return
    }

    val draft = ProfileDraft(name, group, Subgroup.of(subgroup))
    val nameMissing = attemptedSave && name.isBlank()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = { LargeTopAppBar(title = { Text(stringResource(R.string.onboarding_title)) }, scrollBehavior = scrollBehavior) },
        bottomBar = {
            Surface(tonalElevation = 3.dp) {
                Button(
                    onClick = {
                        attemptedSave = true
                        when (val result = draft.validate(groupList.groups)) {
                            is ProfileDraft.Result.Valid -> model.save(result.profile)
                            is ProfileDraft.Result.Invalid ->
                                if (result.problem == ProfileDraft.Problem.EMPTY_NAME) nameFocus.requestFocus() else group = null
                        }
                    },
                    enabled = group != null,
                    modifier = Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(16.dp),
                ) { Text(stringResource(R.string.onboarding_save)) }
            }
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.profile_full_name)) },
                placeholder = { Text(stringResource(R.string.onboarding_name_placeholder)) },
                isError = nameMissing,
                supportingText = {
                    Text(stringResource(if (nameMissing) R.string.onboarding_name_required else R.string.onboarding_name_footer))
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                modifier = Modifier.fillMaxWidth().focusRequester(nameFocus),
            )

            GroupField(groupList, group, onOpen = { pickingGroup = true }, onRetry = { scope.launch { groupList.load(model) } })

            SubgroupSelector(Subgroup.of(subgroup), onSelect = { subgroup = it.number })
        }
    }
}

/** "Группа: ИСП-225а ›" that opens the searchable list, or the load state. */
@Composable
fun GroupField(groupList: GroupListState, selection: String?, onOpen: () -> Unit, onRetry: () -> Unit) {
    OutlinedCard(Modifier.fillMaxWidth()) {
        when (val state = groupList.state) {
            GroupListState.State.Loading -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is GroupListState.State.Failed ->
                ErrorNotice(errorTitle(state.error), errorRecovery(state.error), onRetry, Modifier.padding(16.dp))
            is GroupListState.State.Loaded -> ListItem(
                headlineContent = { Text(stringResource(R.string.profile_group)) },
                supportingContent = { Text(selection ?: stringResource(R.string.onboarding_choose)) },
                trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null) },
                modifier = Modifier.clickable(onClick = onOpen),
            )
        }
    }
}

/** Segmented 1 / 2 / Не указана with an explanation below. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubgroupSelector(selection: Subgroup, onSelect: (Subgroup) -> Unit) {
    val options = listOf(Subgroup.FIRST, Subgroup.SECOND, Subgroup.UNSPECIFIED)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.profile_subgroup), style = MaterialTheme.typography.titleSmall)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            options.forEachIndexed { index, option ->
                SegmentedButton(
                    selected = selection == option,
                    onClick = { onSelect(option) },
                    shape = SegmentedButtonDefaults.itemShape(index, options.size),
                ) {
                    Text(if (option == Subgroup.UNSPECIFIED) subgroupName(option) else option.number.toString())
                }
            }
        }
        Text(
            stringResource(R.string.subgroup_footer),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** Searchable list of all groups, sectioned by course. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupPickerScreen(groups: List<GroupInfo>, selection: String?, onPick: (String) -> Unit, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    var search by rememberSaveable { mutableStateOf("") }
    val filtered = groups.filter { it.name.contains(search.trim(), ignoreCase = true) }
    val sections = filtered.groupBy { it.course }.toSortedMap()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.profile_group)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.action_back))
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            OutlinedTextField(
                value = search,
                onValueChange = { search = it },
                placeholder = { Text(stringResource(R.string.group_search)) },
                leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
            if (filtered.isEmpty()) {
                Text(
                    stringResource(R.string.group_not_found),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(24.dp),
                )
            }
            LazyColumn(Modifier.imePadding()) {
                sections.forEach { (course, items) ->
                    stickyHeader(key = "course-$course") {
                        Surface(Modifier.fillMaxWidth()) {
                            Text(
                                if (course > 0) stringResource(R.string.course_label, course) else stringResource(R.string.course_other),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            )
                        }
                    }
                    items(items, key = { it.name }) { info ->
                        ListItem(
                            headlineContent = { Text(info.name) },
                            trailingContent = {
                                if (info.name == selection) Icon(Icons.Outlined.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            modifier = Modifier.clickable { onPick(info.name) },
                        )
                    }
                }
            }
        }
    }
}
