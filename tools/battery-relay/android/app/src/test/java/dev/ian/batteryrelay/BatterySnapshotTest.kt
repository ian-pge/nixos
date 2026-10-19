package dev.ian.batteryrelay

import org.junit.Assert.*
import org.junit.Test

class BatterySnapshotTest {
    @Test fun sharedWireVector() {
        val bytes = BatterySnapshot(73, true, false).encode(1_700_000_000_000)
        assertEquals("010149070000018bcfe56800", bytes.joinToString("") { "%02x".format(it) })
        assertEquals(12, bytes.size)
    }

    @Test fun unknownsDoNotPretendToBeZeroOrUnplugged() {
        val data = BatterySnapshot(null, null, null).encode(1)
        assertEquals(255, data[2].toInt() and 255)
        assertEquals(0, data[3].toInt())
    }

    @Test fun flagsUseIndependentKnownBits() {
        assertEquals(5, BatterySnapshot(0, false, false).encode(1)[3].toInt())
        assertEquals(15, BatterySnapshot(100, true, true).encode(1)[3].toInt())
        assertEquals(12, BatterySnapshot(50, null, true).encode(1)[3].toInt())
        assertEquals(3, BatterySnapshot(50, true, null).encode(1)[3].toInt())
    }

    @Test fun fullIsPluggedButNotActivelyCharging() {
        assertEquals(BatterySnapshot(100, true, false), BatterySnapshot.fromRaw(100, 100, 2, 5))
    }

    @Test fun pluggedCanBeTrueWhenChargingIsSuspended() {
        assertEquals(BatterySnapshot(80, true, false), BatterySnapshot.fromRaw(80, 100, 1, 4))
    }

    @Test fun malformedRawValuesStayUnknown() {
        assertEquals(BatterySnapshot(null, null, null), BatterySnapshot.fromRaw(-1, 0, -1, 1))
        assertNull(BatterySnapshot.fromRaw(101, 100, 0, 3).percent)
        assertEquals(50, BatterySnapshot.fromRaw(1, 2, 0, 3).percent)
    }

    @Test fun percentAndTimestampAreValidated() {
        assertThrows(IllegalArgumentException::class.java) { BatterySnapshot(101, null, null) }
        assertThrows(IllegalArgumentException::class.java) { BatterySnapshot(-1, null, null) }
        assertThrows(IllegalArgumentException::class.java) { BatterySnapshot(50, null, null).encode(0) }
        assertThrows(IllegalArgumentException::class.java) { BatterySnapshot(50, null, null).encode(9_007_199_254_740_992L) }
        assertThrows(IllegalArgumentException::class.java) { BatterySnapshot(50, null, null).encode(1, 3) }
    }

    @Test fun writeQueueSerializesAndCoalescesUpdates() {
        val queue = SnapshotQueue()
        val first = BatterySnapshot(40, false, false)
        val second = BatterySnapshot(41, true, true)
        val latest = BatterySnapshot(42, true, true)
        queue.update(first)
        assertEquals(first, queue.next())
        queue.update(second)
        queue.update(latest)
        assertNull(queue.next())
        queue.acknowledge()
        assertEquals(latest, queue.next())
        queue.acknowledge()
        assertNull(queue.next())
        queue.update(latest)
        assertNull(queue.next())
    }

    @Test fun reconnectAlwaysSendsInitialSnapshotAgain() {
        val queue = SnapshotQueue()
        val snapshot = BatterySnapshot(40, false, false)
        queue.update(snapshot)
        assertEquals(snapshot, queue.next())
        queue.acknowledge()
        queue.resetConnection()
        assertEquals(snapshot, queue.next())
    }

    @Test fun heartbeatResendsWithoutOverlappingAnActiveWrite() {
        val queue = SnapshotQueue()
        val snapshot = BatterySnapshot(60, false, false)
        queue.update(snapshot)
        assertEquals(snapshot, queue.next())
        queue.refresh()
        assertNull(queue.next())
        queue.acknowledge()
        assertNull(queue.next())
        queue.refresh()
        assertEquals(snapshot, queue.next())
    }
}
