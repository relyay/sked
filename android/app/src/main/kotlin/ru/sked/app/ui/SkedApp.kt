package ru.sked.app.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DateRange
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import ru.sked.app.R
import ru.sked.app.ui.home.HomeScreen
import ru.sked.app.ui.onboarding.OnboardingScreen
import ru.sked.app.ui.profile.ProfileScreen
import ru.sked.app.ui.schedule.ScheduleScreen
import kotlin.time.Duration.Companion.minutes

private enum class Tab(@StringRes val title: Int, val icon: ImageVector) {
    HOME(R.string.tab_home, Icons.Outlined.Home),
    SCHEDULE(R.string.tab_schedule, Icons.Outlined.DateRange),
    PROFILE(R.string.tab_profile, Icons.Outlined.Person),
}

@Composable
fun SkedApp(model: AppViewModel) {
    if (model.profile == null) {
        OnboardingScreen(model)
        return
    }

    // Refresh on launch, on return to the foreground and every 5 minutes while
    // visible; the server polls the PDFs every 2 minutes and 304s keep it cheap.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                model.refresh()
                delay(5.minutes)
            }
        }
    }

    var tab by rememberSaveable { mutableStateOf(Tab.HOME) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = { tab = item },
                        icon = { Icon(item.icon, contentDescription = null) },
                        label = { Text(stringResource(item.title)) },
                    )
                }
            }
        },
    ) { padding ->
        // Each tab draws its own top app bar; only the navigation bar's space
        // is taken here.
        Box(Modifier.padding(bottom = padding.calculateBottomPadding()).consumeWindowInsets(padding)) {
            when (tab) {
                Tab.HOME -> HomeScreen(model)
                Tab.SCHEDULE -> ScheduleScreen(model)
                Tab.PROFILE -> ProfileScreen(model)
            }
        }
    }
}
