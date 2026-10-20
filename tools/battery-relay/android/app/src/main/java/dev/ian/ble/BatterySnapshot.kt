package dev.ian.ble

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

data class BatteryPacket(val snapshot: BatterySnapshot, val kind: Int = BatterySnapshot.PHONE, val sourceTimeMs: Long? = null) {
    init {
        require(kind == BatterySnapshot.PHONE || kind == BatterySnapshot.FITBIT)
        require(if (kind == BatterySnapshot.PHONE) sourceTimeMs == null else sourceTimeMs != null && sourceTimeMs in 1..9_007_199_254_740_991L)
    }
    fun encode(nowMs: Long): ByteArray = snapshot.encode(sourceTimeMs ?: nowMs, kind)
}

/** One indication in flight for both sources; updates are coalesced per device. */
class SnapshotQueue {
    private val latest = mutableMapOf<Int, BatteryPacket>()
    private val acknowledged = mutableMapOf<Int, BatteryPacket>()
    private var inFlight: BatteryPacket? = null
    val phoneSnapshot: BatterySnapshot? get() = latest[BatterySnapshot.PHONE]?.snapshot
    val fitbitPacket: BatteryPacket? get() = latest[BatterySnapshot.FITBIT]

    fun update(snapshot: BatterySnapshot) { update(BatteryPacket(snapshot)) }
    fun update(packet: BatteryPacket) { latest[packet.kind] = packet }
    fun next(): BatteryPacket? {
        if (inFlight != null) return null
        // Establish phone liveness before sending the optional cloud reading.
        for (kind in listOf(BatterySnapshot.PHONE, BatterySnapshot.FITBIT)) {
            val packet = latest[kind] ?: continue
            if (packet != acknowledged[kind]) return packet.also { inFlight = it }
        }
        return null
    }
    fun acknowledge(): BatteryPacket? {
        val sent = inFlight ?: return null
        acknowledged[sent.kind] = sent
        inFlight = null
        // Acknowledged withdrawals need not be repeated forever. If a newer
        // reading arrived while the clear was in flight, keep that new reading.
        if (sent.kind == BatterySnapshot.FITBIT && sent.snapshot == BatterySnapshot(null, null, null)
            && latest[sent.kind] == sent) {
            latest.remove(sent.kind)
            acknowledged.remove(sent.kind)
        }
        return sent
    }
    fun refresh() { acknowledged.clear() }
    fun resetConnection() { acknowledged.clear(); inFlight = null }
}
