package dev.ian.ble

import android.Manifest
import android.annotation.SuppressLint
import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertisingSet
import android.bluetooth.le.AdvertisingSetCallback
import android.bluetooth.le.AdvertisingSetParameters
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.*
import android.util.Log
import java.util.UUID

data class RelayState(
    val running: Boolean = false,
    val broadcasting: Boolean = false,
    val status: String = "Relais arrêté",
    val battery: BatterySnapshot? = null,
    val lastPublishedMs: Long? = null,
)

/** Non-connectable broadcaster. No GATT server, peer, pairing or app heartbeat. */
@SuppressLint("MissingPermission")
class RelayService : Service() {
    inner class LocalBinder : Binder() { val service: RelayService get() = this@RelayService }
    private val handler = Handler(Looper.getMainLooper())
    private val observers = mutableSetOf<(RelayState) -> Unit>()
    private val updates = AdvertisementUpdates()
    private var advertising: AdvertisingSetCallback? = null
    private var advertisingSet: AdvertisingSet? = null
    private var enabled = false
    private var foreground = false
    private var generation = 0
    private var phoneTimeMs = 0L
    private var state = RelayState()
    private val preferences by lazy { getSharedPreferences(PREFERENCES, MODE_PRIVATE) }
    private val manager by lazy { getSystemService(BluetoothManager::class.java) }
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private val fitbit by lazy { FitbitRepository.get(this) }
    private val fitbitObserver: (FitbitState) -> Unit = { refreshAdvertisement() }
    // A deadline for an API operation only; no recurring wakeup/heartbeat.
    private val operationTimeout = Runnable { stopRelay("Le Bluetooth n’a pas confirmé la diffusion. Réactivez le relais.", disable = false) }

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != Intent.ACTION_BATTERY_CHANGED) return
            val snapshot = BatterySnapshot.fromRaw(
                intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1),
                intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1),
                intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1),
                intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN))
            if (snapshot == state.battery) return
            phoneTimeMs = System.currentTimeMillis()
            publish(state.copy(battery = snapshot))
            refreshAdvertisement()
        }
    }
    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (!enabled || intent.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                BluetoothAdapter.STATE_ON -> { refreshAdvertisement(); startAdvertising() }
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                    closeAdvertising()
                    publish(state.copy(broadcasting = false, status = "Bluetooth désactivé — en attente"))
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "Relais de batterie", NotificationManager.IMPORTANCE_LOW))
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(bluetoothReceiver, filter, RECEIVER_EXPORTED)
        else registerReceiver(bluetoothReceiver, filter)
        fitbit.observe(fitbitObserver)
    }
    override fun onBind(intent: Intent): IBinder = LocalBinder()
    fun observe(observer: (RelayState) -> Unit) { observers.add(observer); observer(state) }
    fun removeObserver(observer: (RelayState) -> Unit) { observers.remove(observer) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { stopRelay("Relais arrêté"); return START_NOT_STICKY }
        when (intent?.action) {
            ACTION_START -> Unit
            ACTION_RESUME, null -> if (!preferences.getBoolean(KEY_ENABLED, false)) {
                stopSelf(startId); return START_NOT_STICKY
            }
            else -> { if (!enabled) stopSelf(startId); return if (enabled) START_STICKY else START_NOT_STICKY }
        }
        if (!hasPermissions(this)) { stopRelay("Autorisation Appareils à proximité nécessaire"); return START_NOT_STICKY }
        if (enabled) return START_STICKY
        enabled = true
        preferences.edit().putBoolean(KEY_ENABLED, true).apply()
        try {
            // Required Android service bookkeeping; no POST_NOTIFICATIONS request.
            startForeground(NOTIFICATION_ID, notification("Démarrage de la diffusion BLE…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            foreground = true
            publish(state.copy(running = true, status = "Démarrage de la diffusion BLE…", lastPublishedMs = null))
            fitbit.setRelayActive(true)
            refreshAdvertisement()
        } catch (_: ForegroundServiceStartNotAllowedException) {
            stopRelay("Démarrage bloqué par Android — ouvrez l’application", disable = false)
        } catch (_: SecurityException) { stopRelay("Autorisation Bluetooth retirée") }
        return if (enabled) START_STICKY else START_NOT_STICKY
    }

    private fun refreshAdvertisement() {
        val phone = state.battery ?: return
        val reading = fitbit.state.takeIf { it.enabled && !it.consentNeeded }?.selected
            ?.takeIf { it.percent != null && it.isFresh(System.currentTimeMillis()) }
        updates.desired = BatteryAdvertisement(phone, phoneTimeMs, reading?.percent, reading?.lastSyncMs)
        if (!enabled) return
        if (advertising == null) startAdvertising() else updateAdvertising()
    }
    private fun data(value: BatteryAdvertisement): AdvertiseData = AdvertiseData.Builder()
        .addServiceData(ParcelUuid(serviceUuid(preferences)), value.encode())
        .setIncludeDeviceName(false).setIncludeTxPowerLevel(false).build()

    private fun startAdvertising() {
        if (!enabled || advertising != null || updates.desired == null) return
        try {
            val adapter = manager.adapter
            if (adapter == null) { stopRelay("Bluetooth indisponible"); return }
            if (!adapter.isEnabled) { publish(state.copy(status = "Bluetooth désactivé — en attente")); return }
            val advertiser = adapter.bluetoothLeAdvertiser
            if (advertiser == null) { stopRelay("Annonceur BLE indisponible"); return }
            updates.reset()
            val first = updates.next() ?: return
            val epoch = generation
            val callback = object : AdvertisingSetCallback() {
                private fun current() = enabled && generation == epoch && advertising === this
                override fun onAdvertisingSetStarted(set: AdvertisingSet?, txPower: Int, result: Int) {
                    if (!current()) {
                        // A late successful start must not leak a broadcaster after Stop.
                        if (result == ADVERTISE_SUCCESS) try { advertiser.stopAdvertisingSet(this) } catch (_: RuntimeException) { }
                        return
                    }
                    handler.removeCallbacks(operationTimeout)
                    if (result != ADVERTISE_SUCCESS || set == null) { stopRelay("Diffusion BLE impossible ($result)", disable = false); return }
                    advertisingSet = set
                    acceptedUpdate()
                }
                override fun onAdvertisingDataSet(set: AdvertisingSet, result: Int) {
                    if (!current()) return
                    handler.removeCallbacks(operationTimeout)
                    if (result != ADVERTISE_SUCCESS) { stopRelay("Actualisation BLE impossible ($result)", disable = false); return }
                    acceptedUpdate()
                }
                override fun onAdvertisingSetStopped(set: AdvertisingSet) {
                    if (current()) stopRelay("Diffusion interrompue par Android — réactivez le relais", disable = false)
                }
            }
            advertising = callback
            handler.postDelayed(operationTimeout, 20_000L)
            advertiser.startAdvertisingSet(parameters(), data(first), null, null, null, callback, handler)
        } catch (_: SecurityException) { stopRelay("Autorisation Bluetooth retirée") }
          catch (error: RuntimeException) { Log.w("BLE", "Advertising start failed", error); stopRelay("Diffusion BLE indisponible", disable = false) }
    }
    private fun acceptedUpdate() {
        if (updates.accepted() == null) return
        publish(state.copy(broadcasting = true, status = "Diffusion BLE active — réception passive sur le PC",
            lastPublishedMs = System.currentTimeMillis()))
        updateAdvertising()
    }
    private fun updateAdvertising() {
        val set = advertisingSet ?: return
        val next = updates.next() ?: return
        try {
            handler.postDelayed(operationTimeout, 20_000L)
            set.setAdvertisingData(data(next))
        } catch (_: SecurityException) { stopRelay("Autorisation Bluetooth retirée") }
          catch (_: RuntimeException) { stopRelay("Actualisation BLE indisponible", disable = false) }
    }
    private fun closeAdvertising() {
        generation++
        handler.removeCallbacks(operationTimeout)
        val callback = advertising
        advertising = null
        advertisingSet = null
        updates.reset()
        if (callback != null) try { manager.adapter?.bluetoothLeAdvertiser?.stopAdvertisingSet(callback) } catch (_: RuntimeException) { }
    }
    private fun stopRelay(message: String, disable: Boolean = true) {
        enabled = false
        fitbit.setRelayActive(false)
        if (disable) preferences.edit().putBoolean(KEY_ENABLED, false).apply()
        closeAdvertising()
        foreground = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        publish(state.copy(running = false, broadcasting = false, status = message))
        stopSelf()
    }
    private fun publish(value: RelayState) {
        val changed = value.status != state.status
        if (changed) Log.d("BLE", value.status)
        state = value
        observers.toList().forEach { it(state) }
        if (foreground && changed && notifications.areNotificationsEnabled()) notifications.notify(NOTIFICATION_ID, notification(value.status))
    }
    private fun notification(message: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, RelayService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_battery)
            .setContentTitle("BLE").setContentText(message).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Arrêter", stop).build()).build()
    }
    override fun onDestroy() {
        enabled = false
        fitbit.removeObserver(fitbitObserver)
        fitbit.setRelayActive(false)
        closeAdvertising()
        unregisterReceiver(batteryReceiver)
        unregisterReceiver(bluetoothReceiver)
        observers.clear()
        super.onDestroy()
    }
    companion object {
        const val ACTION_START = "dev.ian.ble.START"
        const val ACTION_RESUME = "dev.ian.ble.RESUME"
        const val ACTION_STOP = "dev.ian.ble.STOP"
        const val PREFERENCES = "relay"
        const val KEY_ENABLED = "enabled"
        fun hasPermissions(context: Context) = listOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
            .all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        fun serviceUuid(preferences: SharedPreferences): UUID {
            val saved = preferences.getString("service_uuid", null)
            if (saved != null) return UUID.fromString(saved)
            return UUID.randomUUID().also { preferences.edit().putString("service_uuid", it.toString()).apply() }
        }
        internal fun parameters(): AdvertisingSetParameters = AdvertisingSetParameters.Builder()
            .setLegacyMode(true).setConnectable(false).setScannable(false)
            .setInterval(AdvertisingSetParameters.INTERVAL_HIGH).setTxPowerLevel(AdvertisingSetParameters.TX_POWER_LOW).build()
        private const val CHANNEL = "battery_relay"
        private const val NOTIFICATION_ID = 1
    }
}
