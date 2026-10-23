package ru.sked.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import ru.sked.app.core.GroupInfo
import ru.sked.app.core.ScheduleResponse
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLEncoder

/** Network failures translated into something a student can act on. */
sealed class ApiError : Exception() {
    data class CannotConnect(val host: String) : ApiError()
    data object TimedOut : ApiError()
    data object Offline : ApiError()
    data object NotLoadedYet : ApiError()
    data class Server(val status: Int, val serverMessage: String?) : ApiError()
    data object BadResponse : ApiError()

    /** Worth retrying automatically. */
    val isTransient: Boolean
        get() = this is TimedOut || this is NotLoadedYet || (this is Server && status >= 500)
}

/**
 * Talks to the skedd server. Conditional requests (ETag → 304) are handled by
 * the installed `HttpResponseCache` because the server sends
 * `Cache-Control: no-cache`.
 */
class ApiClient(private val baseUrl: String, private val maxAttempts: Int = 3) {
    /** All groups of both buildings. */
    suspend fun groups(): List<GroupInfo> = Json.groups(get("/groups"))

    /**
     * The whole known schedule of one group across buildings, and the raw body
     * for the offline cache.
     */
    suspend fun schedule(group: String): Pair<ScheduleResponse, String> {
        val body = get("/schedule?group=" + URLEncoder.encode(group, "UTF-8"))
        val response = runCatching { Json.schedule(body) }.getOrElse { throw ApiError.BadResponse }
        return response to body
    }

    private suspend fun get(path: String): String {
        var attempt = 0
        while (true) {
            attempt++
            try {
                return withContext(Dispatchers.IO) { fetch(URL(baseUrl.trimEnd('/') + path)) }
            } catch (e: ApiError) {
                if (!e.isTransient || attempt >= maxAttempts) throw e
                // Exponential backoff: 0.5 s, 1 s, 2 s…
                delay(500L shl (attempt - 1))
            }
        }
    }

    private fun fetch(url: URL): String {
        val connection = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 10_000
            useCaches = true
            setRequestProperty("Accept", "application/json")
        }
        try {
            val status = connection.responseCode
            if (status in 200..299) {
                return connection.inputStream.bufferedReader().use { it.readText() }
            }
            val body = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            throw if (status == 503) ApiError.NotLoadedYet else ApiError.Server(status, Json.errorMessage(body))
        } catch (e: ApiError) {
            throw e
        } catch (e: SocketTimeoutException) {
            throw ApiError.TimedOut
        } catch (e: IOException) {
            // Includes unknown host and refused connections; the view model
            // turns this into Offline when the device has no network at all.
            throw ApiError.CannotConnect(url.host)
        } finally {
            connection.disconnect()
        }
    }
}
