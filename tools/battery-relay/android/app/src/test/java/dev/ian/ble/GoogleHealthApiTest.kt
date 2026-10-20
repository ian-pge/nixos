package dev.ian.ble

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI

class GoogleHealthApiTest {
    private class Response(url: String, private val body: String, private val status: Int = 200) : HttpURLConnection(URI(url).toURL()) {
        var closed = false
        override fun connect() {}
        override fun disconnect() { closed = true }
        override fun usingProxy() = false
        override fun getResponseCode() = status
        override fun getInputStream() = ByteArrayInputStream(body.toByteArray())
        override fun getErrorStream() = ByteArrayInputStream(body.toByteArray())
    }
    private fun tracker(id: String, level: String = "42") = """{"name":"users/me/pairedDevices/$id","deviceType":"TRACKER","batteryLevel":$level,"deviceVersion":"Fitbit Air","lastSyncTime":"2023-11-14T22:13:20Z"}"""

    @Test fun identityIsCheckedThenPagesAreReadOverHttpsWithoutRedirects() {
        val calls = mutableListOf<Response>()
        val bodies = ArrayDeque(listOf("{\"name\":\"users/me/identity\"}",
            """{"pairedDevices":[${tracker("one")}],"nextPageToken":"a&b?"}""",
            """{"pairedDevices":[${tracker("two", "0")}]}"""))
        val api = GoogleHealthApi { url -> Response(url, bodies.removeFirst()).also { calls.add(it) } }
        val result = api.devices("test-only-token")
        assertEquals(listOf(42, 0), result.map { it.percent })
        assertTrue(calls[0].url.toString().endsWith("/users/me/identity"))
        assertTrue(calls[2].url.toString().contains("pageToken=a%26b%3F"))
        for (call in calls) {
            assertEquals("health.googleapis.com", call.url.host); assertEquals("https", call.url.protocol)
            assertEquals("Bearer test-only-token", call.getRequestProperty("Authorization"))
            assertFalse(call.instanceFollowRedirects); assertTrue(call.closed)
            assertEquals(10000, call.connectTimeout); assertEquals(10000, call.readTimeout)
        }
    }
    @Test fun absentDevicesIsAnEmptyListButMalformedListIsRejected() {
        assertEquals(emptyList<FitbitReading>(), GoogleHealthApi { Response(it, "{}") }.devices("test"))
        var calls = 0
        assertThrows(IOException::class.java) {
            GoogleHealthApi { Response(it, if (calls++ == 0) "{}" else "{\"pairedDevices\":42}") }.devices("test")
        }
    }
    @Test fun nonSuccessfulIdentityStopsBeforeReadingDevicesAndDoesNotLeakBody() {
        var calls = 0
        val error = assertThrows(GoogleHealthApi.Failure::class.java) {
            GoogleHealthApi { calls++; Response(it, """{"error":{"message":"private-sentinel ACCOUNT_NOT_LINKED"}}""", 400) }.devices("test")
        }
        assertEquals(1, calls); assertEquals("ACCOUNT_NOT_LINKED", error.reason)
        assertFalse(error.message!!.contains("private-sentinel"))
    }
    @Test fun invalidJsonHugeBodiesAndRedirectsAreRejected() {
        for ((body, status) in listOf("not-json" to 200, " ".repeat(256 * 1024 + 1) to 200, "{}" to 302)) {
            val responses = mutableListOf<Response>()
            assertThrows(IOException::class.java) {
                GoogleHealthApi { Response(it, body, status).also { response -> responses.add(response) } }.devices("test")
            }
            assertTrue(responses.all { it.closed })
        }
    }
    @Test fun paginationCannotLoopOrReturnPartialSuccess() {
        var calls = 0
        assertThrows(IOException::class.java) {
            GoogleHealthApi { Response(it, if (calls++ == 0) "{}" else """{"pairedDevices":[],"nextPageToken":"same"}""") }.devices("test")
        }
        assertEquals(3, calls)
    }
    @Test fun theOnlyRequestedScopeIsReadOnlySettings() {
        assertEquals("https://www.googleapis.com/auth/googlehealth.settings.readonly", GoogleHealthApi.SCOPE)
    }
}
