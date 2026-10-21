package dev.ian.ble

import android.app.ForegroundServiceStartNotAllowedException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Resume an opted-in relay after first unlock or an app update, never on installation. */
class RelayStartupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val preferences = context.getSharedPreferences(RelayService.PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(RelayService.KEY_ENABLED, false)) {
            Log.d("BLE", "Automatic resume skipped: relay disabled")
            return
        }
        if (!RelayService.hasPermissions(context)) {
            Log.w("BLE", "Automatic resume skipped: Bluetooth permission missing")
            return
        }
        try {
            // The service rechecks the opt-in when handling this request, so a
            // queued boot/update cannot undo the user's subsequent Stop action.
            context.startForegroundService(Intent(context, RelayService::class.java).setAction(RelayService.ACTION_RESUME))
            Log.i("BLE", "Automatic resume requested after ${intent.action}")
        } catch (error: ForegroundServiceStartNotAllowedException) {
            // Respect Android restrictions; no alarm, retry loop or exemption request.
            Log.w("BLE", "Android blocked automatic resume; open the app to resume", error)
        } catch (error: SecurityException) {
            Log.w("BLE", "Automatic resume permission denied; open the app to resume", error)
        }
    }
}
