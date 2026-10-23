package ru.sked.app.ui

import android.app.Application
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import ru.sked.app.BuildConfig
import ru.sked.app.core.GroupInfo
import ru.sked.app.core.Profile
import ru.sked.app.core.ScheduleQuery
import ru.sked.app.core.ScheduleResponse
import ru.sked.app.data.ApiClient
import ru.sked.app.data.ApiError
import ru.sked.app.data.ProfileStore
import ru.sked.app.data.ScheduleCache

/** App-wide state: the local profile and the schedule. */
class AppViewModel(application: Application) : AndroidViewModel(application) {
    sealed interface ScheduleState {
        data object Idle : ScheduleState
        data object Loading : ScheduleState
        data class Loaded(val response: ScheduleResponse) : ScheduleState
        /** Network failed and there is no cached snapshot. */
        data class Failed(val error: ApiError) : ScheduleState
    }

    private val profileStore = ProfileStore(application)
    private val cache = ScheduleCache(application)
    val client = ApiClient(BuildConfig.SERVER_URL)

    var profile by mutableStateOf(profileStore.load())
        private set
    var scheduleState by mutableStateOf<ScheduleState>(ScheduleState.Idle)
        private set
    /** When the shown schedule was downloaded, epoch millis. */
    var dataFetchedAt by mutableStateOf<Long?>(null)
        private set
    /** Set when the shown schedule came from the offline cache. */
    var staleReason by mutableStateOf<ApiError?>(null)
        private set
    var isRefreshing by mutableStateOf(false)
        private set

    init {
        profile?.let { loadCached(it.group) }
    }

    val schedule: ScheduleResponse?
        get() = (scheduleState as? ScheduleState.Loaded)?.response

    val query: ScheduleQuery?
        get() {
            val profile = profile ?: return null
            val schedule = schedule ?: return null
            return ScheduleQuery(schedule.days, profile.group, profile.subgroup)
        }

    fun save(profile: Profile) {
        val groupChanged = profile.group != this.profile?.group
        this.profile = profile
        profileStore.save(profile)
        if (groupChanged) {
            scheduleState = ScheduleState.Idle
            dataFetchedAt = null
            staleReason = null
            loadCached(profile.group)
            refreshAsync()
        }
    }

    fun resetProfile() {
        profile = null
        profileStore.clear()
        cache.clear()
        scheduleState = ScheduleState.Idle
        dataFetchedAt = null
        staleReason = null
    }

    fun refreshAsync() {
        viewModelScope.launch { refresh() }
    }

    /** Downloads the schedule; on failure keeps showing the cached snapshot. */
    suspend fun refresh() {
        val profile = profile ?: return
        if (isRefreshing) return
        isRefreshing = true
        if (schedule == null) scheduleState = ScheduleState.Loading
        try {
            val (response, body) = client.schedule(profile.group)
            // The profile may have changed while the request was in flight.
            if (profile.group != this.profile?.group) return
            cache.save(body, profile.group)
            scheduleState = ScheduleState.Loaded(response)
            dataFetchedAt = System.currentTimeMillis()
            staleReason = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: ApiError) {
            if (profile.group != this.profile?.group) return
            val error = offlineAware(e)
            if (schedule != null) staleReason = error else scheduleState = ScheduleState.Failed(error)
        } finally {
            isRefreshing = false
        }
    }

    suspend fun loadGroups(): Result<List<GroupInfo>> = try {
        Result.success(client.groups())
    } catch (e: CancellationException) {
        throw e
    } catch (e: ApiError) {
        Result.failure(offlineAware(e))
    }

    private fun loadCached(group: String) {
        cache.load(group)?.let { (response, savedAt) ->
            scheduleState = ScheduleState.Loaded(response)
            dataFetchedAt = savedAt
        }
    }

    /** A connection error with no network at all is reported as "offline". */
    private fun offlineAware(error: ApiError): ApiError {
        if (error !is ApiError.CannotConnect) return error
        val connectivity = getApplication<Application>().getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity?.getNetworkCapabilities(connectivity.activeNetwork)
        val online = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        return if (online) error else ApiError.Offline
    }
}
