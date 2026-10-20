package dev.ian.ble

import org.json.JSONObject
import java.io.IOException
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.util.concurrent.CancellationException

/** Only settings/device metadata. No activity, sleep, heart-rate or profile scope. */
class GoogleHealthApi(private val open: (String) -> HttpURLConnection = {
    URI(it).toURL().openConnection() as HttpURLConnection
}) {
    class Failure(val status: Int, val reason: String = "") : IOException("Google Health request failed ($status)")

    fun devices(accessToken: String): List<FitbitReading> {
        // Confirm this Google account is linked to Google Health; discard its identifiers.
        get("/users/me/identity", accessToken)
        val devices = linkedMapOf<String, FitbitReading>()
        val seenTokens = mutableSetOf<String>()
        var pageToken: String? = null
        repeat(10) {
            if (Thread.currentThread().isInterrupted) throw CancellationException()
            val query = "?pageSize=100" + (pageToken?.let { "&pageToken=" + URLEncoder.encode(it, "UTF-8") } ?: "")
            val response = get("/users/me/pairedDevices$query", accessToken)
            val entries = response.optJSONArray("pairedDevices")
            if (response.has("pairedDevices") && entries == null) throw IOException("Invalid device list")
            if (entries != null) for (index in 0 until entries.length()) {
                val value = entries.optJSONObject(index) ?: throw IOException("Invalid device entry")
                FitbitReading.parse(value)?.let { devices[it.id] = it }
            }
            pageToken = (response.opt("nextPageToken") as? String)?.takeIf { it.isNotEmpty() }
            if (pageToken == null) return devices.values.toList()
            if (pageToken.length > 8192 || !seenTokens.add(pageToken)) throw IOException("Invalid pagination")
        }
        throw IOException("Device list exceeds page limit")
    }

    private fun get(path: String, token: String): JSONObject {
        val connection = open("https://health.googleapis.com/v4$path")
        try {
            connection.requestMethod = "GET"
            connection.instanceFollowRedirects = false // Never forward a bearer token to a redirect target.
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.useCaches = false
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Accept", "application/json")
            val code = connection.responseCode
            val stream = if (code == 200) connection.inputStream else connection.errorStream
            val body = stream?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    if (Thread.currentThread().isInterrupted) throw CancellationException()
                    val count = input.read(buffer)
                    if (count == -1) break
                    if (output.size() + count > 256 * 1024) throw IOException("Response exceeds size limit")
                    output.write(buffer, 0, count)
                }
                output.toString("UTF-8")
            } ?: "{}"
            val json = runCatching { JSONObject(body) }.getOrElse { throw IOException("Invalid Google Health response") }
            if (code != 200) {
                // Expose only known error categories, never raw responses, account IDs or tokens.
                val error = json.optJSONObject("error")
                val reasons = listOf("ACCOUNT_NOT_LINKED", "SERVICE_DISABLED", "ACCESS_TOKEN_SCOPE_INSUFFICIENT")
                val reason = reasons.firstOrNull { error?.toString()?.contains(it) == true } ?: ""
                throw Failure(code, reason)
            }
            return json
        } finally { connection.disconnect() }
    }

    companion object { const val SCOPE = "https://www.googleapis.com/auth/googlehealth.settings.readonly" }
}
