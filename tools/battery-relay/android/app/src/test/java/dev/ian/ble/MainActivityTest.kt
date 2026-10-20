package dev.ian.ble

import android.Manifest
import android.app.AlertDialog
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.gms.auth.api.identity.AuthorizationClient
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Status
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.Before
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowAlertDialog
import org.robolectric.shadows.ShadowBuild
import org.robolectric.shadows.ShadowLooper
import java.io.File
import java.lang.reflect.Proxy

/** Local, fictitious UI fixtures. No phone, Bluetooth or Google account is touched. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w448dp-h900dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class MainActivityTest {
    @Test fun applicationIdentityMatchesTheGoogleAndroidClient() {
        assertEquals("dev.ian.ble", RuntimeEnvironment.getApplication().packageName)
    }
    @Test fun appDoesNotRequestNotificationsButKeepsForegroundServicePermissions() {
        val application = RuntimeEnvironment.getApplication()
        val requested = application.packageManager.getPackageInfo(application.packageName,
            PackageManager.GET_PERMISSIONS).requestedPermissions.orEmpty().toSet()
        assertFalse(Manifest.permission.POST_NOTIFICATIONS in requested)
        assertTrue(Manifest.permission.FOREGROUND_SERVICE in requested)
        assertTrue(Manifest.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE in requested)
    }
    @Before fun isolatedProviders() {
        val application = RuntimeEnvironment.getApplication()
        application.getSharedPreferences("fitbit", Context.MODE_PRIVATE).edit().clear().commit()
        application.getSharedPreferences("relay", Context.MODE_PRIVATE).edit().clear()
            .putBoolean(RelayService.KEY_ENABLED, true).putString(RelayService.KEY_ADDRESS, "AA:BB:CC:DD:EE:FF").commit()
        FitbitRepository::class.java.getDeclaredField("instance").apply { isAccessible = true }.set(null, null)
        // A local fake binder, without starting the real BLE/foreground service.
        val service = RelayService()
        shadowOf(application).setComponentNameAndServiceForBindService(ComponentName(application, RelayService::class.java), service.LocalBinder())
    }
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()

    private fun fixture(name: String, action: (MainActivity, ViewGroup) -> Unit) {
        ShadowBuild.setModel("Pixel 8 Pro")
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup().visible()
        val activity = controller.get()
        try {
            val relay = RelayState(running = true, connected = true, status = "Connecté", battery = BatterySnapshot(95, true, true), lastSentMs = System.currentTimeMillis())
            MainActivity::class.java.getDeclaredField("lastRelay").apply { isAccessible = true }.set(activity, relay)
            render(activity)
            val root = activity.findViewById<ViewGroup>(android.R.id.content)
            action(activity, root)
            layout(root)
            ShadowLooper.idleMainLooper(300, java.util.concurrent.TimeUnit.MILLISECONDS)
            val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
            root.draw(Canvas(bitmap))
            val output = File("build/reports/ui/$name.png").apply { requireNotNull(parentFile).mkdirs() }
            output.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        } finally { controller.pause().stop().destroy() }
    }
    private fun render(activity: MainActivity) {
        MainActivity::class.java.getDeclaredMethod("render").apply { isAccessible = true }.invoke(activity)
    }
    private fun layout(root: View) {
        val config = root.resources.configuration
        val density = root.resources.displayMetrics.density
        val width = (config.screenWidthDp * density).toInt()
        val height = (config.screenHeightDp * density).toInt()
        root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, width, height)
    }
    private fun visibleText(root: View) = views(root).filterIsInstance<TextView>().filter { it.isShown }.joinToString("\n") { it.text }

    @Test fun homeIsReadableAndDoesNotExposeTechnicalSetupOrAuthorizeGoogle() = fixture("home") { activity, root ->
        layout(root)
        val text = visibleText(root)
        assertTrue(text.contains("Connecté au PC")); assertTrue(text.contains("Pixel 8 Pro"))
        assertFalse(text.contains("Adresse Bluetooth")); assertFalse(text.contains("googlehealth.settings.readonly"))
        assertFalse(FitbitRepository.get(activity).state.enabled)
        val connect = views(root).filterIsInstance<Button>().first { it.text == "Associer mon Fitbit" }
        connect.performClick()
        val consent = ShadowAlertDialog.getLatestAlertDialog()
        assertTrue(consent.isShowing)
        consent.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        assertFalse(FitbitRepository.get(activity).state.enabled)
    }

    @Test fun settingsRemainActionableWhileRelayRuns() = fixture("settings") { _, root ->
        views(root).filterIsInstance<ImageButton>().first { it.contentDescription == "Ouvrir les réglages" }.performClick()
        layout(root)
        val pc = views(root).filterIsInstance<TextView>().first { it.text == "Ordinateur enregistré" }
        (pc.parent.parent as View).performClick()
        val dialog = ShadowAlertDialog.getLatestAlertDialog()
        assertTrue(dialog.findViewById<TextView>(android.R.id.message).text.contains("Mettez-le en pause"))
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        assertTrue(visibleText(root).contains("Accès Google"))
    }

    @Test fun relayStartsWithoutNotificationPermissionOrPrompt() = fixture("notifications-disabled-fixture") { activity, root ->
        val application = RuntimeEnvironment.getApplication()
        shadowOf(application).grantPermissions(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
        shadowOf(application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertEquals(PackageManager.PERMISSION_DENIED, activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS))
        MainActivity::class.java.getDeclaredField("lastRelay").apply { isAccessible = true }.set(activity, RelayState())
        render(activity)
        // Ignore the fixture's initial service binding; inspect the button's request.
        while (shadowOf(application).nextStartedService != null) { }
        views(root).filterIsInstance<Button>().first { it.text == "Activer le relais" }.performClick()
        val started = shadowOf(application).nextStartedService
        assertNotNull("Starting the relay must not wait for notification consent", started)
        assertEquals(RelayService.ACTION_START, started.action)
        assertEquals(ComponentName(activity, RelayService::class.java), started.component)
    }

    @Test fun googleFailureIntentReachesSdkEvenWhenActivityReportsCanceled() = fixture("auth-error-fixture") { activity, root ->
        val repository = FitbitRepository.get(activity)
        val response = Intent().putExtra("private-fixture", "never-log")
        var decoded = false
        val fake = Proxy.newProxyInstance(AuthorizationClient::class.java.classLoader, arrayOf(AuthorizationClient::class.java)) { _, method, args ->
            assertEquals("getAuthorizationResultFromIntent", method.name)
            assertSame(response, args[0]); decoded = true
            throw ApiException(Status(10))
        } as AuthorizationClient
        FitbitRepository::class.java.getDeclaredField("client\$delegate").apply { isAccessible = true }.set(repository, lazyOf(fake))
        FitbitRepository::class.java.getDeclaredField("waitingForConsent").apply { isAccessible = true }.setBoolean(repository, true)
        activity.handleGoogleAuthorizationResult(ActivityResult(Activity.RESULT_CANCELED, response))
        assertTrue(decoded); assertTrue(repository.state.status.contains("code 10"))
        assertTrue(visibleText(root).contains("Connecté au PC")); assertFalse(repository.state.enabled)
    }

    @Test fun failedIntentSenderLaunchIsNotReportedAsCancellation() = fixture("auth-launch-error-fixture") { activity, root ->
        val repository = FitbitRepository.get(activity)
        FitbitRepository::class.java.getDeclaredField("waitingForConsent").apply { isAccessible = true }.setBoolean(repository, true)
        val data = Intent().putExtra(ActivityResultContracts.StartIntentSenderForResult.EXTRA_SEND_INTENT_EXCEPTION,
            android.content.IntentSender.SendIntentException("test launch failure"))
        activity.handleGoogleAuthorizationResult(ActivityResult(Activity.RESULT_CANCELED, data))
        assertTrue(repository.state.status.contains("Impossible d’ouvrir"))
        assertFalse(repository.state.enabled); assertTrue(visibleText(root).contains("Connecté au PC"))
    }

    @Test fun cloudFixtureShowsSyncDateWithoutClaimingCharging() = fixture("fitbit-fixture") { activity, root ->
        val repository = FitbitRepository.get(activity)
        val reading = FitbitReading("users/me/pairedDevices/test", "Fitbit Air", 42, System.currentTimeMillis() - 900_000)
        FitbitRepository::class.java.getDeclaredField("state").apply { isAccessible = true }.set(repository,
            FitbitState(enabled = true, selected = reading, devices = listOf(reading), status = "Batterie issue de Google Health."))
        render(activity); layout(root)
        val text = visibleText(root)
        assertTrue(text.contains("Fitbit Air")); assertTrue(text.contains("Synchronisé il y a 15 min"))
        assertTrue(text.contains("État de charge non fourni"))
    }

    @Test @Config(qualifiers = "w320dp-h720dp-xhdpi")
    fun narrowScreenAndLargeTextKeepActionsInsideTheScreen() {
        RuntimeEnvironment.setFontScale(1.6f)
        fixture("large-text") { _, root ->
            layout(root)
            for (button in views(root).filterIsInstance<Button>().filter { it.isShown }) {
                assertTrue(button.width > 0)
                assertTrue(button.width <= root.width)
                assertTrue(button.height >= 48 * root.resources.displayMetrics.density)
            }
        }
    }
}
