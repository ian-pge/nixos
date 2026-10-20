package dev.ian.ble

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class InstallationCleanupTest {
    @Test fun cleanupIsIdempotentAndPreservesPhoneAndFitbitSettings() {
        val context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("google_battery_widget", Context.MODE_PRIVATE)
            .edit().putInt("widget_id", 22).putInt("pending_widget_id", 23).commit()
        context.getSharedPreferences("relay", Context.MODE_PRIVATE).edit().putBoolean("keep", true).commit()
        context.getSharedPreferences("fitbit", Context.MODE_PRIVATE).edit().putBoolean("keep", true).commit()
        InstallationCleanup.releaseRetiredWidget(context)
        InstallationCleanup.releaseRetiredWidget(context)
        assertTrue(context.getSharedPreferences("google_battery_widget", Context.MODE_PRIVATE).all.isEmpty())
        assertTrue(context.getSharedPreferences("relay", Context.MODE_PRIVATE).getBoolean("keep", false))
        assertTrue(context.getSharedPreferences("fitbit", Context.MODE_PRIVATE).getBoolean("keep", false))
    }
    @Test fun widgetAndScanningPermissionsAreNotRequested() {
        val context = RuntimeEnvironment.getApplication()
        val permissions = context.packageManager.getPackageInfo(context.packageName,
            PackageManager.GET_PERMISSIONS).requestedPermissions.orEmpty().toSet()
        assertFalse(Manifest.permission.BIND_APPWIDGET in permissions)
        assertFalse(Manifest.permission.BLUETOOTH_SCAN in permissions)
    }
}
