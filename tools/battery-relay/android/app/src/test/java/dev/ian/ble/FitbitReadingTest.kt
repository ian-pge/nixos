package dev.ian.ble

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class FitbitReadingTest {
    private val now = 1_700_000_000_000L
    private fun device(extra: String = "", kind: String = "TRACKER") = JSONObject("""{
        "name":"users/me/pairedDevices/air", "deviceType":"$kind", "deviceVersion":"Fitbit Air"
        $extra
    }""")

    @Test fun exactZeroAndFullAreNotChargingStates() {
        for (percent in listOf(0, 42, 100)) {
            val reading = FitbitReading.parse(device(",\"batteryLevel\":$percent,\"lastSyncTime\":\"2023-11-14T22:13:20Z\""))!!
            assertEquals(percent, reading.percent); assertEquals(now, reading.lastSyncMs)
            assertTrue(reading.isFresh(now)); assertEquals("Fitbit Air", reading.model)
        }
    }
    @Test fun missingMalformedAndCategoricalValuesStayUnknown() {
        for (value in listOf("null", "-1", "101", "42.5", "\"42\"", "true"))
            assertNull(FitbitReading.parse(device(",\"batteryLevel\":$value"))!!.percent)
        assertNull(FitbitReading.parse(device(",\"batteryStatus\":\"High\""))!!.percent)
        assertNull(FitbitReading.parse(device())!!.lastSyncMs)
        assertNull(FitbitReading.parse(device(",\"lastSyncTime\":\"not-a-date\""))!!.lastSyncMs)
    }
    @Test fun onlyTrackersWithValidResourceNamesAreAccepted() {
        assertNull(FitbitReading.parse(device(kind = "SCALE")))
        assertNull(FitbitReading.parse(device(kind = "DEVICE_TYPE_UNSPECIFIED")))
        assertNull(FitbitReading.parse(device().put("name", "https://other.example/tracker")))
        assertNull(FitbitReading.parse(device().put("name", "users/me/pairedDevices/air/extra")))
    }
    @Test fun preservesTimezoneAndFractionalSyncTime() {
        val reading = FitbitReading.parse(device(",\"lastSyncTime\":\"2023-11-14T23:13:20.123456789+01:00\""))!!
        assertEquals(now + 123, reading.lastSyncMs)
    }
    @Test fun staleFutureAndUnknownSyncAreNotFresh() {
        val reading = FitbitReading("users/me/pairedDevices/air", "Fitbit Air", 42, now)
        assertTrue(reading.isFresh(now + FitbitReading.MAX_AGE_MS - 1))
        assertFalse(reading.isFresh(now + FitbitReading.MAX_AGE_MS))
        assertFalse(reading.isFresh(now - FitbitReading.CLOCK_SKEW_MS - 1))
        assertFalse(reading.copy(lastSyncMs = null).isFresh(now))
        assertFalse(reading.copy(lastSyncMs = 0).isFresh(now))
    }
    @Test fun selectionIsUnambiguousAndDoesNotReplaceAMissingSavedDevice() {
        val air = FitbitReading("users/me/pairedDevices/air", "Fitbit Air", 42, now)
        val charge = air.copy(id = "users/me/pairedDevices/charge", model = "Charge 6")
        assertEquals(air, FitbitReading.select(listOf(air, charge), null))
        assertEquals(charge, FitbitReading.select(listOf(air, charge), charge.id))
        assertNull(FitbitReading.select(listOf(air), charge.id))
        assertNull(FitbitReading.select(listOf(air, air.copy(id = "users/me/pairedDevices/air2")), null))
        assertNull(FitbitReading.select(emptyList(), null))
    }
}
