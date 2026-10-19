package dev.ian.batteryrelay

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.app.ForegroundServiceStartNotAllowedException
import android.bluetooth.BluetoothAdapter
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/** Deliberately small native UI: select a PC, start/stop, inspect actual state. */
@SuppressLint("MissingPermission", "SetTextI18n")
class MainActivity : Activity() {
    private var bound = false
    private var relay: RelayService? = null
    private var afterPermission: (() -> Unit)? = null
    private lateinit var statusText: TextView
    private lateinit var batteryText: TextView
    private lateinit var savedText: TextView
    private lateinit var scanText: TextView
    private lateinit var scanButton: Button
    private lateinit var connectButton: Button
    private lateinit var stopButton: Button
    private val preferences by lazy { getSharedPreferences(RelayService.PREFERENCES, MODE_PRIVATE) }
    private val observer: (RelayState) -> Unit = { render(it) }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            relay = (service as RelayService.LocalBinder).service
            relay?.observe(observer)
        }
        override fun onServiceDisconnected(name: ComponentName) { relay = null }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(CRUST)
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }
        val scroll = ScrollView(this).apply { isFillViewport = true; addView(root) }
        setContentView(scroll)
        // Target 36 enforces edge-to-edge: keep all controls clear of system bars/cutouts.
        scroll.setOnApplyWindowInsetsListener { view, insets ->
            val system = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            view.setPadding(system.left, system.top, system.right, system.bottom)
            insets
        }
        root.addView(text("Battery Relay", 30f, TEXT, bold = true))
        root.addView(text("Votre batterie, directement sur votre PC.", 16f, SECONDARY))

        val phoneCard = card()
        phoneCard.addView(text("TÉLÉPHONE", 12f, YELLOW, bold = true))
        batteryText = text("Lecture de la batterie…", 24f, TEXT, bold = true)
        phoneCard.addView(batteryText)
        statusText = text("Relais arrêté", 15f, SECONDARY)
        phoneCard.addView(statusText)
        root.addView(phoneCard)

        val fitbitCard = card()
        fitbitCard.addView(text("FITBIT", 12f, YELLOW, bold = true))
        fitbitCard.addView(text("Non configuré", 20f, TEXT, bold = true))
        fitbitCard.addView(text("L’accès Google Health sera ajouté après sa vérification. Aucune donnée de votre compte n’est lue par cette version.", 14f, SECONDARY))
        root.addView(fitbitCard)

        val pcCard = card()
        pcCard.addView(text("CONNEXION AU PC", 12f, YELLOW, bold = true))
        savedText = text("", 14f, SECONDARY)
        pcCard.addView(savedText)
        updateSavedPc()
        connectButton = button("Activer le relais") {
            withPermissions {
                val address = preferences.getString(RelayService.KEY_ADDRESS, null)
                if (address == null) configurePc()
                else startRelay(address)
            }
        }
        pcCard.addView(connectButton)
        scanButton = button("Configurer le PC") { configurePc() }
        pcCard.addView(scanButton)
        val serviceId = RelayService.serviceUuid(preferences).toString()
        pcCard.addView(text("Identifiant public du téléphone :\n$serviceId", 13f, SECONDARY))
        pcCard.addView(button("Copier l’identifiant") {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Battery Relay", serviceId))
        })
        scanText = text("BLE sans appairage et sans chiffrement. L’adresse du PC est un filtre pratique, pas une authentification : les données peuvent être interceptées ou imitées à proximité.", 14f, SECONDARY)
        pcCard.addView(scanText)
        root.addView(pcCard)

        stopButton = button("Arrêter le relais") {
            startService(Intent(this, RelayService::class.java).setAction(RelayService.ACTION_STOP))
        }
        root.addView(stopButton)
        root.addView(text("BLE uniquement, sans audio ni cloud. Les changements sont envoyés immédiatement, avec un signal de présence toutes les 60 secondes quand Android le permet. Une notification reste visible pendant le relais.", 13f, SECONDARY))
        root.addView(text("Le relais activé reprend automatiquement après un redémarrage, dès le premier déverrouillage, et après une mise à jour de l’application. « Arrêter le relais » désactive aussi cette reprise. La tenue en veille prolongée reste à tester.", 13f, SECONDARY))
    }

    override fun onStart() {
        super.onStart()
        bound = bindService(Intent(this, RelayService::class.java), connection, Context.BIND_AUTO_CREATE)
    }

    override fun onStop() {
        relay?.removeObserver(observer)
        relay = null
        if (bound) { unbindService(connection); bound = false }
        super.onStop()
    }

    private fun render(state: RelayState) {
        connectButton.isEnabled = !state.running
        scanButton.isEnabled = !state.running
        val battery = state.battery
        val charge = when {
            battery?.charging == true -> "En charge"
            battery?.plugged == true -> if (battery.charging == false) "Branché · charge inactive" else "Branché · charge inconnue"
            battery?.plugged == false -> "Débranché"
            else -> "Branchement inconnu"
        }
        batteryText.text = "${battery?.percent?.let { "$it %" } ?: "—"}  ·  $charge"
        val lastSent = state.lastSentMs?.let {
            "\nDernier envoi : ${DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it))}"
        } ?: ""
        statusText.text = state.status + lastSent
        stopButton.isEnabled = state.running
    }

    private fun updateSavedPc() {
        savedText.text = preferences.getString(RelayService.KEY_ADDRESS, null)?.let { "PC enregistré : $it" }
            ?: "Aucun PC enregistré"
    }

    private fun bluetoothPermissionsGranted() = listOf(
        Manifest.permission.BLUETOOTH_ADVERTISE,
        Manifest.permission.BLUETOOTH_CONNECT,
    ).all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun withPermissions(action: () -> Unit) {
        val required = mutableListOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
        if (Build.VERSION.SDK_INT >= 33) required.add(Manifest.permission.POST_NOTIFICATIONS)
        val missing = required.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) action()
        else {
            afterPermission = action
            requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val action = afterPermission
        afterPermission = null
        if (bluetoothPermissionsGranted()) {
            // Notification permission is helpful but is not an Android prerequisite for an FGS.
            action?.invoke()
        } else scanText.text = "Autorisez les appareils à proximité dans les paramètres de cette application."
    }

    private fun configurePc() {
        val input = EditText(this).apply {
            isSingleLine = true
            hint = "AA:BB:CC:DD:EE:FF"
            setText(preferences.getString(RelayService.KEY_ADDRESS, ""))
        }
        AlertDialog.Builder(this).setTitle("Adresse Bluetooth du PC")
            .setMessage("Aucun appairage système nécessaire. L’adresse est visible dans les paramètres Bluetooth du PC.")
            .setView(input).setNegativeButton("Annuler", null)
            .setPositiveButton("Enregistrer") { _, _ ->
                val address = input.text.toString().trim().uppercase(Locale.ROOT)
                if (BluetoothAdapter.checkBluetoothAddress(address)) {
                    preferences.edit().putString(RelayService.KEY_ADDRESS, address).apply()
                    updateSavedPc()
                } else scanText.text = "Adresse invalide : utilisez le format AA:BB:CC:DD:EE:FF."
            }.show()
    }

    private fun startRelay(address: String) {
        preferences.edit().putString(RelayService.KEY_ADDRESS, address).apply()
        updateSavedPc()
        try {
            startForegroundService(Intent(this, RelayService::class.java)
                .setAction(RelayService.ACTION_START).putExtra(RelayService.EXTRA_ADDRESS, address))
        } catch (_: ForegroundServiceStartNotAllowedException) {
            scanText.text = "Revenez dans l’application et appuyez sur Connecter pour démarrer le relais."
        } catch (_: SecurityException) {
            scanText.text = "Autorisation Bluetooth nécessaire pour démarrer le relais."
        }
    }

    private fun text(value: String, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(6), 0, dp(6))
    }

    private fun button(label: String, action: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setTextColor(CRUST)
        backgroundTintList = ColorStateList.valueOf(YELLOW)
        minHeight = dp(48)
        setOnClickListener { action() }
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    }

    private fun card() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(18), dp(14), dp(18), dp(14))
        background = GradientDrawable().apply { setColor(BASE); cornerRadius = dp(22).toFloat() }
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(18)
            bottomMargin = dp(6)
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val PERMISSION_REQUEST = 1
        private val CRUST = Color.rgb(24, 25, 38)
        private val BASE = Color.rgb(36, 39, 58)
        private val TEXT = Color.rgb(202, 211, 245)
        private val SECONDARY = Color.rgb(165, 173, 203)
        private val YELLOW = Color.rgb(238, 212, 159)
    }
}
