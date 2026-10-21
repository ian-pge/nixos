package dev.ian.ble

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Local Android battery semantics, independent of the transport. */
data class BatterySnapshot(val percent: Int?, val plugged: Boolean?, val charging: Boolean?) {
    init { require(percent == null || percent in 0..100) }
    val flags: Int get() = (if (plugged != null) 1 else 0) or
        (if (plugged == true) 2 else 0) or (if (charging != null) 4 else 0) or
        (if (charging == true) 8 else 0)

    companion object {
        fun fromRaw(level: Int, scale: Int, plugged: Int, status: Int): BatterySnapshot {
            val percent = if (level >= 0 && scale > 0 && level <= scale)
                ((level.toLong() * 100) / scale).toInt() else null
            val charging = when (status) { 2 -> true; 3, 4, 5 -> false; else -> null }
            return BatterySnapshot(percent, plugged.takeIf { it >= 0 }?.let { it != 0 }, charging)
        }
    }
}

/** V2: one non-connectable advertisement, both sources atomically.
 * 12 payload bytes + 16-byte installation UUID + AD length/type = 30 bytes.
 * Non-connectable legacy advertising has no Flags AD and fits the 31-byte limit.
 * Times are original source times, floored to Unix seconds, never a heartbeat.
 */
data class BatteryAdvertisement(
    val phone: BatterySnapshot,
    val phoneTimeMs: Long,
    val fitbitPercent: Int? = null,
    val fitbitTimeMs: Long? = null,
) {
    init {
        require(phoneTimeMs / 1000 in 1..0xffff_ffffL)
        require(fitbitPercent == null || fitbitPercent in 0..100)
        require(if (fitbitPercent == null) fitbitTimeMs == null
            else fitbitTimeMs != null && fitbitTimeMs / 1000 in 1..0xffff_ffffL)
    }
    fun encode(): ByteArray = ByteBuffer.allocate(12).order(ByteOrder.BIG_ENDIAN)
        .put(2.toByte()).put((phone.percent ?: 255).toByte()).put(phone.flags.toByte())
        .put((fitbitPercent ?: 255).toByte()).putInt((phoneTimeMs / 1000).toInt())
        .putInt(((fitbitTimeMs ?: 0) / 1000).toInt()).array()
}

/** Serializes asynchronous AdvertisingSet writes, coalescing rapid changes.
 * Acceptance means installed in the radio, NOT received by a PC.
 */
internal class AdvertisementUpdates {
    var desired: BatteryAdvertisement? = null
    var applied: BatteryAdvertisement? = null
        private set
    private var pending: BatteryAdvertisement? = null
    fun next(): BatteryAdvertisement? {
        if (pending != null || desired == applied) return null
        return desired?.also { pending = it }
    }
    fun accepted(): BatteryAdvertisement? = pending?.also { applied = it; pending = null }
    fun reset() { pending = null; applied = null }
}
