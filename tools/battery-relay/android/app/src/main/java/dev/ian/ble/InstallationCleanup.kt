package dev.ian.ble

import android.appwidget.AppWidgetHost
import android.content.Context
import android.util.Log

/** Upgrade cleanup only. No widget source, host listener or battery fallback.
 * Delete precisely BLE's old host, never another app's/home-screen widgets.
 */
internal object InstallationCleanup {
    fun releaseRetiredWidget(context: Context) {
        val name = "google_battery_widget"
        val preferences = context.getSharedPreferences(name, Context.MODE_PRIVATE)
        if (preferences.all.isEmpty()) return
        try {
            AppWidgetHost(context, 4421).deleteHost()
            context.deleteSharedPreferences(name)
        } catch (_: RuntimeException) {
            // Keep the marker to retry on the next start; do not lose the
            // ability to clean an allocation if the system service is down.
            Log.w("BLE", "Le nettoyage de l’ancien widget sera réessayé au prochain démarrage.")
        }
    }
}
