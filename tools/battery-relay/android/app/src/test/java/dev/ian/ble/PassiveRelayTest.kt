package dev.ian.ble

import android.Manifest
import android.content.Context
import android.content.Intent
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PassiveRelayTest {
    @Test fun radioIsLegacyNonconnectableAndNonscannable() {
        val p=RelayService.parameters()
        assertTrue(p.isLegacy); assertFalse(p.isConnectable);assertFalse(p.isScannable)
        assertEquals(1600,p.interval) // 1600 * 0.625 ms, controller-managed repetition.
    }
    @Test fun bootAndUpdateResumeNeedOptInButNoPcAddress() {
        val context=RuntimeEnvironment.getApplication()
        shadowOf(context).grantPermissions(Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_ADVERTISE)
        val prefs=context.getSharedPreferences(RelayService.PREFERENCES,Context.MODE_PRIVATE)
        prefs.edit().clear().putBoolean(RelayService.KEY_ENABLED,true).commit()
        while(shadowOf(context).nextStartedService!=null) { }
        val receiver=RelayStartupReceiver()
        for (action in listOf(Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_MY_PACKAGE_REPLACED)) {
            receiver.onReceive(context,Intent(action))
            assertEquals(RelayService.ACTION_RESUME,shadowOf(context).nextStartedService.action)
        }
        prefs.edit().putBoolean(RelayService.KEY_ENABLED,false).commit()
        receiver.onReceive(context,Intent(Intent.ACTION_BOOT_COMPLETED))
        assertNull(shadowOf(context).nextStartedService)
    }
}
