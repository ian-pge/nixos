package dev.ian.ble

import org.json.JSONObject
import java.time.Instant

/** The cloud sync time is never replaced by the time we fetched or relayed it. */
data class FitbitReading(val id: String, val model: String, val percent: Int?, val lastSyncMs: Long?) {
    fun isFresh(nowMs: Long): Boolean = lastSyncMs != null && lastSyncMs > 0 &&
        lastSyncMs <= nowMs + CLOCK_SKEW_MS && nowMs - lastSyncMs < MAX_AGE_MS

    companion object {
        const val MAX_AGE_MS = 6 * 60 * 60 * 1000L
        const val CLOCK_SKEW_MS = 5 * 60 * 1000L
        private val RESOURCE = Regex("users/[^/]+/pairedDevices/[^/]+")

        fun parse(value: JSONObject): FitbitReading? {
            // Do not accidentally select an Aria Air scale, or an unknown device type.
            if (value.opt("deviceType") != "TRACKER") return null
            val id = value.opt("name") as? String ?: return null
            if (!RESOURCE.matches(id)) return null
            val rawLevel = value.opt("batteryLevel")
            val percent = if (rawLevel is Number && rawLevel.toDouble().isFinite() &&
                rawLevel.toDouble() in 0.0..100.0 && rawLevel.toDouble() % 1.0 == 0.0) rawLevel.toInt() else null
            val sync = (value.opt("lastSyncTime") as? String)?.let {
                runCatching { Instant.parse(it).toEpochMilli() }.getOrNull()
            }?.takeIf { it in 1..9_007_199_254_740_991L }
            val model = (value.opt("deviceVersion") as? String)?.trim()?.take(80)?.takeIf { it.isNotEmpty() } ?: "Fitbit"
            return FitbitReading(id, model, percent, sync)
        }

        fun select(devices: List<FitbitReading>, savedId: String?): FitbitReading? {
            // A disappeared, explicitly chosen device must never silently become another tracker.
            if (savedId != null) return devices.singleOrNull { it.id == savedId }
            return devices.singleOrNull() ?: devices.filter {
                it.model.equals("Fitbit Air", true) || it.model.equals("Google Fitbit Air", true) || it.model.equals("Air", true)
            }.singleOrNull()
        }
    }
}
