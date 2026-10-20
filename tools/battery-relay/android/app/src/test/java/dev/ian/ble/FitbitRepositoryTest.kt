package dev.ian.ble

import android.content.Context
import android.content.Intent
import android.app.Activity
import android.os.Looper
import com.google.android.gms.auth.api.identity.AuthorizationClient
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Status
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.android.gms.tasks.Tasks
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog
import java.lang.reflect.Proxy
import java.time.Duration

/** Google is faked at the SDK boundary; tests never authorize a real account. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@LooperMode(LooperMode.Mode.PAUSED)
class FitbitRepositoryTest {
    private val authorization = TaskCompletionSource<AuthorizationResult>()
    private val revocation = TaskCompletionSource<Void>()
    private var authCalls = 0
    private var revokeCalls = 0
    private var decodeCalls = 0
    private var decodedIntent: Intent? = null
    private var decodeError: Exception = ApiException(Status(10, "private-diagnostic-sentinel"))
    private fun repository(enabled: Boolean = false): FitbitRepository {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("fitbit", Context.MODE_PRIVATE).edit().clear().putBoolean("enabled", enabled).commit()
        FitbitRepository::class.java.getDeclaredField("instance").apply { isAccessible = true }.set(null, null)
        val fake = Proxy.newProxyInstance(AuthorizationClient::class.java.classLoader, arrayOf(AuthorizationClient::class.java)) { _, method, args ->
            when (method.name) {
                "authorize" -> { authCalls++; authorization.task }
                "revokeAccess" -> { revokeCalls++; revocation.task }
                "clearToken" -> Tasks.forResult<Void>(null)
                "getAuthorizationResultFromIntent" -> { decodeCalls++; decodedIntent = args[0] as Intent; throw decodeError }
                else -> error("Unexpected SDK call: ${method.name}")
            }
        } as AuthorizationClient
        val repository = FitbitRepository.get(context)
        FitbitRepository::class.java.getDeclaredField("client\$delegate").apply { isAccessible = true }.set(repository, lazyOf(fake))
        return repository
    }
    private fun idle() = shadowOf(Looper.getMainLooper()).idle()
    private fun waiting(repo: FitbitRepository) {
        FitbitRepository::class.java.getDeclaredField("waitingForConsent").apply { isAccessible = true }.setBoolean(repo, true)
        FitbitRepository::class.java.getDeclaredField("state").apply { isAccessible = true }.set(repo, repo.state.copy(consentNeeded = true))
    }

    @Test fun canceledActivityCanContainAnSdkErrorThatMustNotBeDiscarded() {
        val repo = repository(); waiting(repo)
        val data = Intent().putExtra("sensitive-test-extra", "never-log-this-value")
        repo.completeAuthorization(data, Activity.RESULT_CANCELED)
        assertEquals(1, decodeCalls); assertSame(data, decodedIntent)
        assertTrue(repo.state.status.contains("code 10")); assertFalse(repo.state.status.contains("annulée"))
        assertFalse(repo.state.enabled); assertNull(repo.state.selected)
        val logs = ShadowLog.getLogsForTag("BLEAuth").joinToString("\n") { it.msg }
        assertFalse(logs.contains("never-log-this-value")); assertFalse(logs.contains("private-diagnostic-sentinel"))
        assertTrue(logs.contains("sdk_failure code=10"))
    }

    @Test fun emptyResultsAreNotClaimedToBeVoluntaryCancellationOrSuccess() {
        val repo = repository()
        for (resultCode in listOf(Activity.RESULT_CANCELED, Activity.RESULT_OK)) {
            waiting(repo); repo.completeAuthorization(null, resultCode)
            assertFalse(repo.state.enabled); assertFalse(repo.state.busy); assertTrue(repo.state.consentNeeded)
            assertTrue(repo.state.status.contains("sans résultat")); assertFalse(repo.state.status.contains("annulée"))
        }
        assertEquals(0, decodeCalls)
    }

    @Test fun sdkCancellationAndMalformedReplyHaveDifferentDiagnostics() {
        val repo = repository(); waiting(repo)
        decodeError = ApiException(Status(16))
        repo.completeAuthorization(Intent(), Activity.RESULT_CANCELED)
        assertTrue(repo.state.status.contains("code 16")); assertFalse(repo.state.enabled)
        waiting(repo); decodeError = ApiException(Status(7))
        repo.completeAuthorization(Intent(), Activity.RESULT_CANCELED)
        assertTrue(repo.state.status.contains("code 7")); assertFalse(repo.state.status.contains("expirée"))
        waiting(repo); decodeError = IllegalArgumentException("do-not-log-this")
        repo.completeAuthorization(Intent(), Activity.RESULT_OK)
        assertTrue(repo.state.status.contains("illisible")); assertFalse(repo.state.enabled)
        assertTrue(ShadowLog.getLogsForTag("BLEAuth").none { it.msg.contains("do-not-log-this") })
    }

    @Test fun resultsFromAClosedAuthorizationAreIgnored() {
        val repo = repository()
        val before = repo.state
        repo.completeAuthorization(Intent(), Activity.RESULT_OK)
        assertEquals(before, repo.state); assertEquals(0, decodeCalls)
    }

    @Test fun startingLocalRelayWithoutFitbitOptInNeverContactsGoogle() {
        val repo = repository()
        repo.setRelayActive(true); repo.refresh(); idle()
        assertEquals(0, authCalls); assertFalse(repo.state.enabled); assertFalse(repo.state.busy)
    }

    @Test fun missingClientConfigurationProducesActionableErrorNotAFakeDevice() {
        val repo = repository()
        repo.connect { fail("Must not launch a consent screen for an SDK failure") }
        assertTrue(repo.state.busy)
        authorization.setException(ApiException(Status(10))); idle()
        assertFalse(repo.state.busy); assertTrue(repo.state.status.contains("Google Cloud"))
        assertNull(repo.state.selected); assertFalse(repo.state.enabled)
    }

    @Test fun lateAuthorizationCannotRestoreDataAfterDisconnect() {
        val repo = repository(true)
        val reading = FitbitReading("users/me/pairedDevices/air", "Fitbit Air", 42, System.currentTimeMillis())
        FitbitRepository::class.java.getDeclaredField("state").apply { isAccessible = true }.set(repo,
            FitbitState(enabled = true, selected = reading, devices = listOf(reading)))
        repo.connect {}
        repo.disconnect()
        assertNull(repo.state.selected); assertTrue(repo.state.devices.isEmpty()); assertFalse(repo.state.enabled)
        revocation.setResult(null); idle()
        val stopped = repo.state
        authorization.setException(ApiException(Status(7))); idle()
        assertEquals(stopped, repo.state); assertFalse(repo.state.revocationFailed)
        assertEquals(1, revokeCalls)
    }

    @Test fun stoppedRelayDoesNotContinueCloudPolling() {
        val repo = repository(true)
        repo.setRelayActive(true)
        authorization.setException(ApiException(Status(7))); idle()
        repo.setRelayActive(false)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMinutes(16))
        assertEquals(1, authCalls)
    }

    @Test fun revocationTimeoutIsVisibleAndDoesNotBlockTheUiForever() {
        val repo = repository(true)
        repo.disconnect()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(46))
        assertFalse(repo.state.busy); assertFalse(repo.state.enabled); assertTrue(repo.state.revocationFailed)
        assertTrue(RuntimeEnvironment.getApplication().getSharedPreferences("fitbit", Context.MODE_PRIVATE).getBoolean("revoke_pending", false))
        val before = repo.state
        revocation.setResult(null); idle()
        assertEquals(before, repo.state)
        repo.connect { fail("A pending revocation must be resolved before reconnecting") }
        assertEquals(0, authCalls)
    }
}
