package dev.ian.ble

import org.junit.Assert.*
import org.junit.Test

class BatterySnapshotTest {
    private fun packet(percent:Int=73)=BatteryAdvertisement(BatterySnapshot(percent,true,false),1_700_000_000_000,42,1_699_999_100_000)
    @Test fun sharedWireVectorFitsNonconnectableLegacyAdvertisement() {
        val bytes=packet().encode()
        assertEquals("0249072a6553f1006553ed7c",bytes.joinToString("") { "%02x".format(it) })
        assertEquals(12,bytes.size)
        assertTrue(2+16+bytes.size<=31)
    }
    @Test fun unknownsRemainUnknownAndFitbitWithdrawalIsExplicit() {
        val bytes=BatteryAdvertisement(BatterySnapshot(null,null,null),1000).encode()
        assertEquals(255,bytes[1].toInt() and 255)
        assertEquals(0,bytes[2].toInt())
        assertEquals(255,bytes[3].toInt() and 255)
        assertArrayEquals(byteArrayOf(0,0,0,0),bytes.copyOfRange(8,12))
    }
    @Test fun flagsHaveIndependentKnownBits() {
        assertEquals(5,BatterySnapshot(0,false,false).flags)
        assertEquals(15,BatterySnapshot(100,true,true).flags)
        assertEquals(12,BatterySnapshot(50,null,true).flags)
        assertEquals(3,BatterySnapshot(50,true,null).flags)
    }
    @Test fun fullAndSuspendedChargeAreNotActiveCharging() {
        assertEquals(BatterySnapshot(100,true,false),BatterySnapshot.fromRaw(100,100,2,5))
        assertEquals(BatterySnapshot(80,true,false),BatterySnapshot.fromRaw(80,100,1,4))
    }
    @Test fun malformedRawValuesStayUnknown() {
        assertEquals(BatterySnapshot(null,null,null),BatterySnapshot.fromRaw(-1,0,-1,1))
        assertNull(BatterySnapshot.fromRaw(101,100,0,3).percent)
        assertEquals(50,BatterySnapshot.fromRaw(1,2,0,3).percent)
    }
    @Test fun validatesPercentAndUnsignedSecondsWithoutSilentOverflow() {
        assertThrows(IllegalArgumentException::class.java) { BatterySnapshot(101,null,null) }
        assertThrows(IllegalArgumentException::class.java) { BatteryAdvertisement(BatterySnapshot(10,null,null),0) }
        assertThrows(IllegalArgumentException::class.java) { BatteryAdvertisement(BatterySnapshot(10,null,null),0x1_0000_0000L*1000) }
        assertThrows(IllegalArgumentException::class.java) { packet().copy(fitbitPercent=null) }
        assertThrows(IllegalArgumentException::class.java) { packet().copy(fitbitTimeMs=null) }
        val last=packet().copy(phoneTimeMs=0xffff_ffffL*1000).encode()
        assertArrayEquals(byteArrayOf(-1,-1,-1,-1),last.copyOfRange(4,8))
    }
    @Test fun timestampsAreFlooredNotRetimestampedOnResend() {
        val a=packet().copy(phoneTimeMs=1_700_000_000_999,fitbitTimeMs=1_699_999_100_999)
        assertArrayEquals(packet().encode(),a.encode())
        assertArrayEquals(a.encode(),a.encode())
    }
    @Test fun advertisingUpdatesAreSerializedAndCoalesced() {
        val q=AdvertisementUpdates()
        q.desired=packet(40);assertEquals(packet(40),q.next())
        q.desired=packet(41);q.desired=packet(42);assertNull(q.next())
        assertEquals(packet(40),q.accepted());assertEquals(packet(42),q.next())
        assertEquals(packet(42),q.accepted());assertNull(q.next())
        q.desired=packet(42);assertNull(q.next())
    }
    @Test fun returningToAppliedValueDuringPendingUpdateIsNotLost() {
        val q=AdvertisementUpdates()
        q.desired=packet(40);q.next();q.accepted()
        q.desired=packet(41);q.next();q.desired=packet(40);q.accepted()
        assertEquals(packet(40),q.next())
    }
    @Test fun bluetoothRestartUsesLatestDataWithoutChangingSourceTime() {
        val q=AdvertisementUpdates();q.desired=packet();q.next();q.accepted()
        q.reset();assertEquals(packet(),q.next());assertEquals(packet(),q.accepted())
        assertEquals(1_699_999_100_000,q.applied!!.fitbitTimeMs)
    }
}
