package dev.ian.ble

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
        assertEquals(first, queue.next()?.snapshot)
        queue.update(second)
        queue.update(latest)
        assertNull(queue.next())
        queue.acknowledge()
        assertEquals(latest, queue.next()?.snapshot)
        queue.acknowledge()
        assertNull(queue.next())
        queue.update(latest)
        assertNull(queue.next())
    }

    @Test fun reconnectAlwaysSendsInitialSnapshotAgain() {
        val queue = SnapshotQueue()
        val snapshot = BatterySnapshot(40, false, false)
        queue.update(snapshot)
        assertEquals(snapshot, queue.next()?.snapshot)
        queue.acknowledge()
        queue.resetConnection()
        assertEquals(snapshot, queue.next()?.snapshot)
    }

    @Test fun heartbeatResendsWithoutOverlappingAnActiveWrite() {
        val queue = SnapshotQueue()
        val snapshot = BatterySnapshot(60, false, false)
        queue.update(snapshot)
        assertEquals(snapshot, queue.next()?.snapshot)
        queue.refresh()
        assertNull(queue.next())
        queue.acknowledge()
        assertNull(queue.next())
        queue.refresh()
        assertEquals(snapshot, queue.next()?.snapshot)
    }

    @Test fun bothSourcesShareOneIndicationSlotAndRetainSourceTime() {
        val queue = SnapshotQueue()
        val phone = BatterySnapshot(71, true, false)
        val fitbit = BatteryPacket(BatterySnapshot(42, null, null), BatterySnapshot.FITBIT, 1_700_000_000_000)
        queue.update(fitbit); queue.update(phone)
        assertEquals(BatterySnapshot.PHONE, queue.next()?.kind)
        assertNull(queue.next()); queue.acknowledge()
        assertEquals(fitbit, queue.next())
        assertEquals("01022a000000018bcfe56800", fitbit.encode(1_800_000_000_000).joinToString("") { "%02x".format(it) })
        queue.update(BatterySnapshot(72, true, true))
        assertNull(queue.next()); queue.acknowledge()
        assertEquals(72, queue.next()?.snapshot?.percent); queue.acknowledge()
        assertNull(queue.next())
        queue.resetConnection()
        assertEquals(BatterySnapshot.PHONE, queue.next()?.kind); queue.acknowledge()
        assertEquals(fitbit, queue.next())
    }

    @Test fun clearingFitbitDoesNotClearPhoneAndNewSyncIsNotDeduplicated() {
        val queue = SnapshotQueue()
        val first = BatteryPacket(BatterySnapshot(42, null, null), BatterySnapshot.FITBIT, 100)
        queue.update(first); assertEquals(first, queue.next()); queue.acknowledge()
        val next = first.copy(sourceTimeMs = 200)
        queue.update(next); assertEquals(next, queue.next()); queue.acknowledge()
        queue.update(BatterySnapshot(80, false, false))
        val clear = BatteryPacket(BatterySnapshot(null, null, null), BatterySnapshot.FITBIT, 300)
        queue.update(clear)
        assertEquals(80, queue.next()?.snapshot?.percent); queue.acknowledge()
        assertEquals(clear, queue.next()); queue.acknowledge()
        assertEquals(80, queue.phoneSnapshot?.percent)
        assertNull(queue.fitbitPacket)
        queue.refresh(); assertEquals(BatterySnapshot.PHONE, queue.next()?.kind); queue.acknowledge()
        assertNull(queue.next())
    }
}
