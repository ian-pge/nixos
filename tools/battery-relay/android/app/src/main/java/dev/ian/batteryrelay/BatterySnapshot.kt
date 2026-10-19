package dev.ian.batteryrelay

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

/** No Android dependency: wire format and state semantics are JVM-testable. */
data class BatterySnapshot(
    val percent: Int?,
    val plugged: Boolean?,
    val charging: Boolean?,
) {
    init { require(percent == null || percent in 0..100) }

    fun encode(timestampMs: Long, kind: Int = PHONE): ByteArray {
        require(timestampMs in 1..9_007_199_254_740_991L)
        require(kind == PHONE || kind == FITBIT)
        val flags = (if (plugged != null) 1 else 0) or
            (if (plugged == true) 2 else 0) or
            (if (charging != null) 4 else 0) or
            (if (charging == true) 8 else 0)
        return ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN)
            .put(1.toByte()).put(kind.toByte()).put((percent ?: 255).toByte())
            .put(flags.toByte()).putLong(timestampMs).array()
    }

    companion object {
        const val PHONE = 1
        const val FITBIT = 2
        val BATTERY_UUID: UUID = UUID.fromString("d973f2e0-b19e-4f19-9a67-6c414c65f802")

        fun fromRaw(level: Int, scale: Int, plugged: Int, status: Int): BatterySnapshot {
            val percentage = if (level >= 0 && scale > 0 && level <= scale) {
                ((level.toLong() * 100L) / scale).toInt()
            } else null
            // Android BatteryManager: 1 unknown, 2 charging, 3 discharging,
            // 4 not charging, 5 full. Full is not active charging.
            val activeCharge = when (status) {
                2 -> true
                3, 4, 5 -> false
                else -> null
            }
            return BatterySnapshot(percentage, plugged.takeIf { it >= 0 }?.let { it != 0 }, activeCharge)
        }
    }
}

/** One write in flight; newer readings supersede pending readings, not acknowledgements. */
class SnapshotQueue {
    var latest: BatterySnapshot? = null
        private set
    private var acknowledged: BatterySnapshot? = null
    private var inFlight: BatterySnapshot? = null

    fun update(snapshot: BatterySnapshot) { latest = snapshot }
    fun next(): BatterySnapshot? {
        if (inFlight != null || latest == acknowledged) return null
        return latest?.also { inFlight = it }
    }
    fun acknowledge() { acknowledged = inFlight; inFlight = null }
    fun refresh() { acknowledged = null }
    fun resetConnection() { acknowledged = null; inFlight = null }
}
