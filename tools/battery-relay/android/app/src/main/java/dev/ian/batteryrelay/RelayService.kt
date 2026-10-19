package dev.ian.batteryrelay

import android.Manifest
import android.annotation.SuppressLint
import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
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
    val status: String = "Relais arrêté",
    val battery: BatterySnapshot? = null,
    val lastSentMs: Long? = null,
)

/** Unpaired BLE peripheral. Address filtering is a convenience, not authentication. */
@SuppressLint("MissingPermission")
class RelayService : Service() {
    inner class LocalBinder : Binder() { val service: RelayService get() = this@RelayService }
    private val handler = Handler(Looper.getMainLooper())
    private val observers = mutableSetOf<(RelayState) -> Unit>()
    private val queue = SnapshotQueue()
    private var server: BluetoothGattServer? = null
    private var characteristic: BluetoothGattCharacteristic? = null
    private var subscriber: BluetoothDevice? = null
    private var advertising: AdvertiseCallback? = null
    private var enabled = false
    private var foreground = false
    private var generation = 0
    private var address: String? = null
    private var state = RelayState()
    private val preferences by lazy { getSharedPreferences(PREFERENCES, MODE_PRIVATE) }
    private val manager by lazy { getSystemService(BluetoothManager::class.java) }
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private val heartbeat = Runnable { queue.refresh(); sendNext() }
    private val sendTimeout = Runnable {
        val device = subscriber
        subscriber = null
        queue.resetConnection()
        if (device != null) try { server?.cancelConnection(device) } catch (_: SecurityException) { }
        status("PC déconnecté — en attente")
        startAdvertising()
    }

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != Intent.ACTION_BATTERY_CHANGED) return
            val snapshot = BatterySnapshot.fromRaw(
                intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1),
                intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1),
                intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1),
                intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN),
            )
            queue.update(snapshot)
            publish(state.copy(battery = snapshot))
            sendNext()
        }
    }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (!enabled) return
            when (intent.action) {
                BluetoothAdapter.ACTION_STATE_CHANGED -> when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                    BluetoothAdapter.STATE_ON -> openServer()
                    BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                        closeServer()
                        status("Bluetooth désactivé — en attente")
                    }
                }
            }
        }
    }

    private fun approved(device: BluetoothDevice): Boolean = try {
        enabled && device.address == address
    } catch (_: SecurityException) { false }

    // Binder callbacks are serialized onto the main looper. Closed-server
    // callbacks cannot mutate a later session, even for the same PC.
    private fun callback(epoch: Int) = object : BluetoothGattServerCallback() {
        private fun dispatch(block: () -> Unit) { handler.post { if (enabled && generation == epoch) block() } }
        override fun onServiceAdded(result: Int, service: BluetoothGattService) = dispatch {
            if (result != BluetoothGatt.GATT_SUCCESS) stopRelay("Création du service BLE impossible ($result)")
            else startAdvertising()
        }
        override fun onConnectionStateChange(device: BluetoothDevice, result: Int, newState: Int) = dispatch {
            Log.d("BatteryRelay", "BLE server connection result=$result state=$newState approvedAddress=${device.address == address}")
            // Android can report links also used by other apps (e.g. Fitbit).
            // Ignore those; never disconnect another device to enforce our ACL.
            if (device.address != address) return@dispatch
            if (newState == BluetoothProfile.STATE_CONNECTED) status("PC connecté — en attente de lecture")
            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                subscriber = null
                queue.resetConnection()
                handler.removeCallbacks(heartbeat)
                handler.removeCallbacks(sendTimeout)
                status("PC déconnecté — en attente")
                startAdvertising()
            }
        }
        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int,
                                                 value: BluetoothGattCharacteristic) = dispatch {
            val payload = queue.latest?.encode(System.currentTimeMillis())
            val result = when {
                !approved(device) -> BluetoothGatt.GATT_INSUFFICIENT_AUTHORIZATION
                value.uuid != BatterySnapshot.BATTERY_UUID -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                offset != 0 -> BluetoothGatt.GATT_INVALID_OFFSET
                payload == null -> BluetoothGatt.GATT_FAILURE
                else -> BluetoothGatt.GATT_SUCCESS
            }
            // Unencrypted by explicit owner choice; this address can be spoofed.
            server?.sendResponse(device, requestId, result, offset, if (result == 0) payload else null)
            if (result == 0) publish(state.copy(status = "Connecté — batterie lue par le PC", lastSentMs = System.currentTimeMillis()))
        }
        override fun onDescriptorReadRequest(device: BluetoothDevice, requestId: Int, offset: Int,
                                             descriptor: BluetoothGattDescriptor) = dispatch {
            val result = when {
                !approved(device) -> BluetoothGatt.GATT_INSUFFICIENT_AUTHORIZATION
                descriptor.uuid != CCCD -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                offset != 0 -> BluetoothGatt.GATT_INVALID_OFFSET
                else -> BluetoothGatt.GATT_SUCCESS
            }
            server?.sendResponse(device, requestId, result, offset, if (result != 0) null else
                if (subscriber?.address == device.address) BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)
        }
        override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
                                              preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) = dispatch {
            val enable = value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)
            val disable = value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)
            val result = when {
                !approved(device) -> BluetoothGatt.GATT_INSUFFICIENT_AUTHORIZATION
                descriptor.uuid != CCCD || preparedWrite || !responseNeeded -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                offset != 0 -> BluetoothGatt.GATT_INVALID_OFFSET
                !enable && !disable -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
                else -> BluetoothGatt.GATT_SUCCESS
            }
            // Only this descriptor is writable; no pairing or encryption required.
            if (responseNeeded) server?.sendResponse(device, requestId, result, offset, null)
            if (result == 0) {
                subscriber = if (enable) device else null
                queue.resetConnection()
                handler.removeCallbacks(heartbeat)
                handler.removeCallbacks(sendTimeout)
                if (enable) { stopAdvertising(); status("Connecté — abonnement du PC actif"); sendNext() }
                else { status("PC non abonné — en attente"); startAdvertising() }
            }
        }
        override fun onNotificationSent(device: BluetoothDevice, result: Int) = dispatch {
            if (subscriber?.address != device.address) return@dispatch
            handler.removeCallbacks(sendTimeout)
            if (result != BluetoothGatt.GATT_SUCCESS) { sendTimeout.run(); return@dispatch }
            queue.acknowledge()
            publish(state.copy(status = "Connecté — batterie transmise", lastSentMs = System.currentTimeMillis()))
            handler.removeCallbacks(heartbeat)
            handler.postDelayed(heartbeat, HEARTBEAT_MS)
            sendNext()
        }
    }

    override fun onCreate() {
        super.onCreate()
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "Relais de batterie", NotificationManager.IMPORTANCE_LOW))
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(bluetoothReceiver, filter, RECEIVER_EXPORTED)
        else registerReceiver(bluetoothReceiver, filter)
    }
    override fun onBind(intent: Intent): IBinder = LocalBinder()
    fun observe(observer: (RelayState) -> Unit) { observers.add(observer); observer(state) }
    fun removeObserver(observer: (RelayState) -> Unit) { observers.remove(observer) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { stopRelay("Relais arrêté"); return START_NOT_STICKY }
        when (intent?.action) {
            ACTION_START -> Unit // Only an explicit user action may enable a stopped relay.
            ACTION_RESUME, null -> if (!preferences.getBoolean(KEY_ENABLED, false)) {
                stopSelf(startId)
                return START_NOT_STICKY
            }
            else -> {
                if (!enabled) stopSelf(startId)
                return if (enabled) START_STICKY else START_NOT_STICKY
            }
        }
        if (!hasPermissions(this)) { stopRelay("Autorisation Appareils à proximité nécessaire"); return START_NOT_STICKY }
        val requested = intent?.getStringExtra(EXTRA_ADDRESS) ?: preferences.getString(KEY_ADDRESS, null)
        if (requested == null || !BluetoothAdapter.checkBluetoothAddress(requested)) {
            stopRelay("Enregistrez l’adresse Bluetooth du PC dans l’application"); return START_NOT_STICKY
        }
        if (enabled && address == requested) return START_STICKY
        closeServer()
        address = requested
        enabled = true
        preferences.edit().putString(KEY_ADDRESS, requested).putBoolean(KEY_ENABLED, true).apply()
        try {
            startForeground(NOTIFICATION_ID, notification("Démarrage du relais BLE…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            foreground = true
            publish(state.copy(running = true, status = "Démarrage du relais BLE…", lastSentMs = null))
            openServer()
        } catch (_: ForegroundServiceStartNotAllowedException) {
            stopRelay("Démarrage bloqué par Android — ouvrez l’application", disable = false)
        } catch (_: SecurityException) { stopRelay("Autorisation Bluetooth retirée") }
        return if (enabled) START_STICKY else START_NOT_STICKY
    }

    private fun openServer() {
        closeServer()
        if (!enabled || !hasPermissions(this)) return
        try {
            val adapter = manager.adapter
            if (adapter == null) { stopRelay("Bluetooth indisponible"); return }
            if (!adapter.isEnabled) { status("Bluetooth désactivé — en attente"); return }
            if (!adapter.isMultipleAdvertisementSupported) { stopRelay("Mode périphérique BLE indisponible"); return }
            val value = BluetoothGattCharacteristic(BatterySnapshot.BATTERY_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_INDICATE,
                BluetoothGattCharacteristic.PERMISSION_READ)
            value.addDescriptor(BluetoothGattDescriptor(CCCD,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
            characteristic = value
            val service = BluetoothGattService(serviceUuid(preferences), BluetoothGattService.SERVICE_TYPE_PRIMARY)
            service.addCharacteristic(value)
            server = manager.openGattServer(this, callback(generation))
            if (server?.addService(service) != true) stopRelay("Impossible de démarrer le service BLE")
        } catch (_: SecurityException) { stopRelay("Autorisation Bluetooth retirée") }
    }
    private fun startAdvertising() {
        if (!enabled || server == null || advertising != null) return
        val epoch = generation
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                handler.post { if (generation == epoch && enabled) status("Relais BLE actif — en attente du PC") }
            }
            override fun onStartFailure(errorCode: Int) {
                handler.post { if (generation == epoch && enabled) stopRelay("Annonce BLE impossible ($errorCode)") }
            }
        }
        try {
            val advertiser = manager.adapter?.bluetoothLeAdvertiser ?: run { stopRelay("Annonceur BLE indisponible"); return }
            advertising = callback
            advertiser.startAdvertising(AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_LOW).setConnectable(true).setTimeout(0).build(),
                AdvertiseData.Builder().addServiceUuid(ParcelUuid(serviceUuid(preferences)))
                    .setIncludeDeviceName(false).build(), callback)
        } catch (_: SecurityException) { stopRelay("Autorisation Bluetooth retirée") }
          catch (_: IllegalStateException) { stopRelay("Bluetooth indisponible") }
    }
    private fun stopAdvertising() {
        val previous = advertising
        advertising = null
        if (previous != null) try { manager.adapter?.bluetoothLeAdvertiser?.stopAdvertising(previous) }
        catch (_: SecurityException) { } catch (_: IllegalStateException) { }
    }
    private fun sendNext() {
        val device = subscriber ?: return
        val value = characteristic ?: return
        val gatt = server ?: return
        if (!approved(device)) { sendTimeout.run(); return }
        val snapshot = queue.next() ?: return
        try {
            val bytes = snapshot.encode(System.currentTimeMillis())
            val accepted = if (Build.VERSION.SDK_INT >= 33) {
                gatt.notifyCharacteristicChanged(device, value, true, bytes) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                value.value = bytes
                @Suppress("DEPRECATION")
                gatt.notifyCharacteristicChanged(device, value, true)
            }
            if (!accepted) { sendTimeout.run(); return }
            handler.postDelayed(sendTimeout, 20_000L)
        } catch (_: SecurityException) { stopRelay("Autorisation Bluetooth retirée") }
    }
    private fun closeServer() {
        generation++
        handler.removeCallbacks(heartbeat)
        handler.removeCallbacks(sendTimeout)
        stopAdvertising()
        subscriber = null
        characteristic = null
        queue.resetConnection()
        try { server?.close() } catch (_: SecurityException) { }
        server = null
    }
    private fun stopRelay(message: String, disable: Boolean = true) {
        enabled = false
        if (disable) preferences.edit().putBoolean(KEY_ENABLED, false).apply()
        closeServer()
        foreground = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        publish(state.copy(running = false, status = message))
        stopSelf()
    }
    private fun status(message: String) = publish(state.copy(status = message))
    private fun publish(value: RelayState) {
        val changed = value.status != state.status
        if (changed) Log.d("BatteryRelay", value.status)
        state = value
        observers.toList().forEach { it(value) }
        if (foreground && changed) notifications.notify(NOTIFICATION_ID, notification(value.status))
    }
    private fun notification(message: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, RelayService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_battery)
            .setContentTitle("Battery Relay").setContentText(message).setContentIntent(open)
            .setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Arrêter", stop).build()).build()
    }
    override fun onDestroy() {
        enabled = false
        closeServer()
        unregisterReceiver(batteryReceiver)
        unregisterReceiver(bluetoothReceiver)
        observers.clear()
        super.onDestroy()
    }
    companion object {
        const val ACTION_START = "dev.ian.batteryrelay.START"
        const val ACTION_RESUME = "dev.ian.batteryrelay.RESUME"
        const val ACTION_STOP = "dev.ian.batteryrelay.STOP"
        const val EXTRA_ADDRESS = "address"
        const val PREFERENCES = "relay"
        const val KEY_ADDRESS = "pc_address"
        const val KEY_ENABLED = "enabled"
        fun hasPermissions(context: Context) = listOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
            .all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        // Public installation identifier: lets the PC find this phone despite
        // rotating BLE addresses. This is NOT a secret or an authentication key.
        fun serviceUuid(preferences: SharedPreferences): UUID {
            val saved = preferences.getString("service_uuid", null)
            if (saved != null) return UUID.fromString(saved)
            val value = UUID.randomUUID()
            preferences.edit().putString("service_uuid", value.toString()).apply()
            return value
        }
        private const val CHANNEL = "battery_relay"
        private const val NOTIFICATION_ID = 1
        private const val HEARTBEAT_MS = 60_000L
        private val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
