package dev.ian.ble

import android.Manifest
import android.annotation.SuppressLint
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
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.ActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import dev.ian.ble.RelayUi.CRUST
import dev.ian.ble.RelayUi.GREEN
import dev.ian.ble.RelayUi.MAUVE
import dev.ian.ble.RelayUi.MUTED
import dev.ian.ble.RelayUi.RED
import dev.ian.ble.RelayUi.SURFACE
import dev.ian.ble.RelayUi.TEXT
import dev.ian.ble.RelayUi.YELLOW
import dev.ian.ble.RelayUi.background
import dev.ian.ble.RelayUi.button
import dev.ian.ble.RelayUi.card
import dev.ian.ble.RelayUi.column
import dev.ian.ble.RelayUi.dp
import dev.ian.ble.RelayUi.icon
import dev.ian.ble.RelayUi.iconButton
import dev.ian.ble.RelayUi.row
import dev.ian.ble.RelayUi.space
import dev.ian.ble.RelayUi.text
import java.security.MessageDigest
import java.text.DateFormat
import java.util.Date
import java.util.Locale

@SuppressLint("SetTextI18n")
class MainActivity : ComponentActivity() {
    private var bound = false
    private var relay: RelayService? = null
    private var afterPermission: (() -> Unit)? = null
    private var showingSettings = false
    private var lastRelay = RelayState()
    private val handler = Handler(Looper.getMainLooper())
    private val preferences by lazy { getSharedPreferences(RelayService.PREFERENCES, MODE_PRIVATE) }
    private val fitbit by lazy { FitbitRepository.get(this) }
    private val backToHome = object : OnBackPressedCallback(false) {
        override fun handleOnBackPressed() { showPage(false) }
    }
    private val googleAuthorization = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult(), ::handleGoogleAuthorizationResult)
    internal fun handleGoogleAuthorizationResult(result: ActivityResult) {
        // Google can include its SDK error in RESULT_CANCELED. Never discard
        // that intent: the SDK, not the activity result code, parses the outcome.
        if (result.data?.hasExtra(ActivityResultContracts.StartIntentSenderForResult.EXTRA_SEND_INTENT_EXCEPTION) == true)
            fitbit.authorizationLaunchFailed()
        else fitbit.completeAuthorization(result.data, result.resultCode)
    }
    private val bluetoothAuthorization = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val action = afterPermission; afterPermission = null
        if (RelayService.hasPermissions(this)) action?.invoke()
        else info("Autorisation nécessaire", "Autorisez les appareils à proximité pour transmettre la batterie en Bluetooth.")
    }
    private lateinit var toolbarTitle: TextView
    private lateinit var toolbarLogo: ImageView
    private lateinit var toolbar: LinearLayout
    private lateinit var toolbarAction: ImageButton
    private lateinit var home: ScrollView
    private lateinit var settings: ScrollView
    private lateinit var connectionTitle: TextView
    private lateinit var connectionDetail: TextView
    private lateinit var connectionDot: View
    private lateinit var relayButton: Button
    private lateinit var phoneGauge: BatteryGauge
    private lateinit var phoneCharge: TextView
    private lateinit var phoneDetail: TextView
    private lateinit var fitbitGauge: BatteryGauge
    private lateinit var fitbitTitle: TextView
    private lateinit var fitbitStatus: TextView
    private lateinit var fitbitSync: TextView
    private lateinit var fitbitBody: LinearLayout
    private lateinit var fitbitAction: Button
    private lateinit var fitbitChoose: Button
    private lateinit var fitbitRefresh: ImageButton
    private lateinit var googleDisconnect: Button
    private lateinit var pcSummary: TextView
    private lateinit var autoStartSummary: TextView
    private val relayObserver: (RelayState) -> Unit = { lastRelay = it; render() }
    private val fitbitObserver: (FitbitState) -> Unit = { render() }
    private val refreshLabels = object : Runnable {
        override fun run() { render(); handler.postDelayed(this, 15_000L) }
    }
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            relay = (service as RelayService.LocalBinder).service
            relay?.observe(relayObserver)
        }
        override fun onServiceDisconnected(name: ComponentName) {
            relay = null; lastRelay = RelayState(status = "Reconnexion au service…"); render()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        InstallationCleanup.releaseRetiredWidget(this)
        val root = column(this).apply { setBackgroundColor(CRUST) }
        toolbar = row(this).apply { setPadding(dp(24), dp(16), dp(24), dp(16)) }
        toolbarTitle = text(this, getString(R.string.app_name), 25f, TEXT, true)
        toolbarLogo = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            layoutParams = LinearLayout.LayoutParams(dp(42), dp(42)).apply { marginEnd = dp(12) }
        }
        toolbar.addView(toolbarTitle, LinearLayout.LayoutParams(0, -2, 1f))
        toolbarAction = iconButton(this, "settings", "Ouvrir les réglages") { showPage(!showingSettings) }
        toolbar.addView(toolbarAction)
        root.addView(toolbar)
        val pages = FrameLayout(this)
        home = page { buildHome(it) }
        settings = page { buildSettings(it) }
        pages.addView(home); pages.addView(settings)
        root.addView(pages, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        root.setOnApplyWindowInsetsListener { view, insets ->
            val system = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            view.setPadding(system.left, system.top, system.right, system.bottom)
            insets
        }
        onBackPressedDispatcher.addCallback(this, backToHome)
        showPage(savedInstanceState?.getBoolean("settings") == true)
        render()
    }

    private fun page(build: (LinearLayout) -> Unit): ScrollView {
        val canvas = FrameLayout(this)
        val content = object : LinearLayout(this) {
            override fun onMeasure(widthSpec: Int, heightSpec: Int) {
                val max = minOf(MeasureSpec.getSize(widthSpec), dp(620))
                super.onMeasure(MeasureSpec.makeMeasureSpec(max, MeasureSpec.EXACTLY), heightSpec)
            }
        }.apply { orientation = LinearLayout.VERTICAL; setPadding(dp(24), dp(8), dp(24), dp(28)) }
        canvas.addView(content, FrameLayout.LayoutParams(-1, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        build(content)
        return ScrollView(this).apply {
            isFillViewport = true; isVerticalScrollBarEnabled = false
            addView(canvas); layoutParams = FrameLayout.LayoutParams(-1, -1)
        }
    }

    private fun buildHome(root: LinearLayout) {
        root.addView(text(this, "Vos batteries. Un seul endroit.", 15f, MUTED))
        root.addView(space(this, 24))
        val connectionCard = card(this)
        val heading = row(this)
        connectionDot = View(this).apply { background = background(this@MainActivity, MUTED, 10) }
        heading.addView(connectionDot, LinearLayout.LayoutParams(dp(9), dp(9)).apply { marginEnd = dp(10) })
        connectionTitle = text(this, "Relais en pause", 16f, TEXT, true)
        heading.addView(connectionTitle, LinearLayout.LayoutParams(0, -2, 1f))
        heading.addView(icon(this, "monitor", MUTED, 22))
        connectionCard.addView(heading)
        connectionCard.addView(space(this, 9))
        connectionDetail = text(this, "", 13f, MUTED)
        connectionCard.addView(connectionDetail)
        connectionCard.addView(space(this, 18))
        relayButton = button(this, "Activer le relais") {
            if (lastRelay.running) startService(Intent(this, RelayService::class.java).setAction(RelayService.ACTION_STOP))
            else withPermissions {
                val address = preferences.getString(RelayService.KEY_ADDRESS, null)
                if (address == null) configurePc(startAfterSave = true) else startRelay(address)
            }
        }
        connectionCard.addView(relayButton)
        root.addView(connectionCard)
        root.addView(section("VOS APPAREILS"))
        val phoneCard = card(this)
        phoneCard.addView(deviceHeading("phone", Build.MODEL, "Ce téléphone", YELLOW))
        phoneCard.addView(space(this, 20))
        val phoneBody = batteryRow()
        val phoneLabels = column(this)
        phoneCharge = text(this, "Lecture…", 19f, TEXT, true)
        phoneDetail = text(this, "", 13f, MUTED)
        phoneLabels.addView(phoneCharge); phoneLabels.addView(space(this, 8)); phoneLabels.addView(phoneDetail)
        phoneGauge = BatteryGauge(this)
        addBatteryBody(phoneBody, phoneLabels, phoneGauge)
        phoneCard.addView(phoneBody)
        phoneCard.addView(space(this, 16))
        phoneCard.addView(text(this, "SOURCE LOCALE  ·  BLUETOOTH LE", 10f, MUTED).apply { letterSpacing = .08f })
        root.addView(phoneCard)
        val fitbitCard = card(this)
        val fitbitHeading = deviceHeading("watch", "Votre Fitbit", "Google Health", MAUVE)
        fitbitTitle = (fitbitHeading.getChildAt(1) as LinearLayout).getChildAt(0) as TextView
        fitbitRefresh = iconButton(this, "refresh", "Actualiser la batterie du Fitbit") { fitbit.refresh() }
        fitbitHeading.addView(fitbitRefresh)
        fitbitCard.addView(fitbitHeading)
        fitbitCard.addView(space(this, 18))
        fitbitBody = batteryRow()
        val fitbitLabels = column(this)
        fitbitLabels.addView(text(this, "Dernière mesure", 18f, TEXT, true)); fitbitLabels.addView(space(this, 8))
        fitbitSync = text(this, "", 13f, MUTED); fitbitLabels.addView(fitbitSync)
        fitbitGauge = BatteryGauge(this)
        addBatteryBody(fitbitBody, fitbitLabels, fitbitGauge)
        fitbitCard.addView(fitbitBody)
        fitbitStatus = text(this, "", 13f, MUTED).apply { setPadding(0, dp(10), 0, dp(14)) }
        fitbitCard.addView(fitbitStatus)
        fitbitAction = button(this, "Associer mon Fitbit", MAUVE) {
            if (fitbit.state.revocationFailed) showPage(true)
            else if (fitbit.state.enabled && !fitbit.state.consentNeeded) fitbit.refresh() else connectFitbit()
        }
        fitbitCard.addView(fitbitAction)
        fitbitChoose = button(this, "Choisir le bracelet", MAUVE, true) { chooseFitbit() }
        fitbitChoose.layoutParams = LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(10) }
        fitbitCard.addView(fitbitChoose)
        root.addView(fitbitCard)
        root.addView(text(this, "Le téléphone reste local. Le Fitbit utilise Google Health, uniquement avec votre autorisation.", 12f, MUTED))
    }

    private fun buildSettings(root: LinearLayout) {
        root.addView(text(this, "Une fois configuré, le relais s’occupe du reste.", 15f, MUTED))
        root.addView(space(this, 24)); root.addView(section("CONNEXION"))
        val pc = card(this)
        pcSummary = settingsRow(pc, "monitor", "Ordinateur enregistré", "") { configurePc() }
        settingsRow(pc, "copy", "Identifiant du téléphone", "Copier l’identifiant public utilisé par le récepteur PC") {
            copy("BLE", RelayService.serviceUuid(preferences).toString())
        }
        autoStartSummary = settingsRow(pc, "refresh", "Reprise automatique", "") {
            info("Reprise automatique", "Le relais activé reprend après le premier déverrouillage suivant un redémarrage, ainsi qu’après une mise à jour.\n\n« Mettre en pause » désactive aussi cette reprise. Un arrêt forcé dans Android doit être suivi d’une réactivation manuelle.")
        }
        root.addView(pc)
        root.addView(section("FITBIT & GOOGLE"))
        val google = card(this)
        settingsRow(google, "watch", "Accès Google", "Configuration initiale et autorisation des appareils") { googleSetup() }
        settingsRow(google, "refresh", "Fréquence & fraîcheur", "Google : 15 min · aucune mesure inventée") {
            info("Des mesures datées", "Téléphone : envoi à chaque changement de batterie et signal de présence environ toutes les 60 secondes.\n\nFitbit : lecture de Google Health toutes les 15 minutes quand le relais fonctionne. Le bracelet doit d’abord se synchroniser avec Google Health ; ce n’est pas une lecture BLE directe du bracelet.\n\nL’heure d’origine est conservée. Après 6 heures sans synchronisation, le widget Fitbit est masqué sur le PC. Son état de charge n’est pas fourni par cette API.")
        }
        googleDisconnect = button(this, "Dissocier le Fitbit", RED, true) {
            AlertDialog.Builder(this).setTitle("Dissocier le Fitbit ?")
                .setMessage("Arrêter sa synchronisation, effacer les données locales de cette intégration et retirer son accès Google. Le relais du téléphone restera actif.")
                .setNegativeButton("Annuler", null).setPositiveButton("Dissocier") { _, _ -> fitbit.disconnect() }.show()
        }
        google.addView(space(this, 8)); google.addView(googleDisconnect); root.addView(google)
        root.addView(section("CONFIDENTIALITÉ"))
        val privacy = card(this)
        privacy.addView(text(this, "Seulement les batteries", 18f, TEXT, true)); privacy.addView(space(this, 10))
        privacy.addView(text(this, "Ni sommeil, ni activité, ni rythme cardiaque. L’accès Google est limité aux paramètres et appareils associés. Aucun jeton Google n’est envoyé au PC.", 13f, MUTED))
        privacy.addView(space(this, 14))
        privacy.addView(text(this, "Le lien BLE est sans appairage et sans chiffrement. L’adresse du PC est un filtre, pas une authentification : les échanges peuvent être interceptés ou imités à proximité.", 13f, MUTED))
        root.addView(privacy)
        val version = packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
        root.addView(text(this, "${getString(R.string.app_name)}  ·  $version", 12f, MUTED).apply { gravity = Gravity.CENTER })
    }

    private fun section(value: String) = text(this, value, 11f, MUTED, true).apply {
        letterSpacing = .12f; setPadding(dp(4), dp(4), 0, dp(14))
    }
    private fun deviceHeading(glyph: String, title: String, subtitle: String, accent: Int): LinearLayout {
        val row = row(this)
        val tile = FrameLayout(this).apply { background = background(this@MainActivity, SURFACE, 16) }
        tile.addView(icon(this, glyph, accent), FrameLayout.LayoutParams(dp(25), dp(25), Gravity.CENTER))
        row.addView(tile, LinearLayout.LayoutParams(dp(48), dp(48)).apply { marginEnd = dp(14) })
        val labels = column(this)
        labels.addView(text(this, title, 18f, TEXT, true)); labels.addView(space(this, 4)); labels.addView(text(this, subtitle, 12f, MUTED))
        row.addView(labels, LinearLayout.LayoutParams(0, -2, 1f))
        return row
    }
    private fun batteryRow() = row(this).apply {
        if (resources.configuration.fontScale > 1.25 || resources.configuration.screenWidthDp < 360) orientation = LinearLayout.VERTICAL
    }
    private fun addBatteryBody(row: LinearLayout, labels: LinearLayout, gauge: BatteryGauge) {
        if (row.orientation == LinearLayout.HORIZONTAL) {
            row.addView(labels, LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = dp(12) })
            row.addView(gauge, LinearLayout.LayoutParams(dp(134), dp(134)))
        } else {
            row.addView(labels, LinearLayout.LayoutParams(-1, -2))
            row.addView(gauge, LinearLayout.LayoutParams(dp(150), dp(150)).apply { topMargin = dp(16); gravity = Gravity.CENTER_HORIZONTAL })
        }
    }
    private fun settingsRow(parent: LinearLayout, glyph: String, title: String, subtitle: String, action: () -> Unit): TextView {
        val row = row(this).apply {
            minimumHeight = dp(72); setPadding(0, dp(10), 0, dp(10)); isFocusable = true
            setOnClickListener { action() }
            val attr = android.util.TypedValue(); theme.resolveAttribute(android.R.attr.selectableItemBackground, attr, true)
            setBackgroundResource(attr.resourceId)
        }
        row.addView(icon(this, glyph, MUTED, 22), LinearLayout.LayoutParams(dp(22), dp(22)).apply { marginEnd = dp(14) })
        val labels = column(this)
        labels.addView(text(this, title, 14f, TEXT, true)); labels.addView(space(this, 5))
        val detail = text(this, subtitle, 12f, MUTED); labels.addView(detail)
        row.addView(labels, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(icon(this, "chevron", MUTED, 18), LinearLayout.LayoutParams(dp(18), dp(18)).apply { marginStart = dp(8) })
        parent.addView(row)
        return detail
    }

    private fun render() {
        if (!::phoneGauge.isInitialized) return
        val state = lastRelay
        val battery = state.battery
        val accent = if (battery?.plugged == true) GREEN else if ((battery?.percent ?: 100) < 40) RED else YELLOW
        phoneGauge.setBattery(battery?.percent, accent)
        phoneCharge.text = when { battery?.charging == true -> "En charge"; battery?.plugged == true -> "Branché"; battery?.plugged == false -> "Sur batterie"; else -> "État inconnu" }
        phoneDetail.text = when { battery?.plugged == true && battery.charging == false -> "Charge inactive ou batterie pleine"; battery?.charging == true -> "Alimentation externe détectée"; else -> "Niveau exact fourni par Android" }
        connectionTitle.text = when { state.connected -> "Connecté au PC"; state.running -> "En attente du PC"; else -> "Relais en pause" }
        connectionDot.background = background(this, if (state.connected) GREEN else if (state.running) YELLOW else MUTED, 10)
        connectionDetail.text = if (state.connected && state.lastSentMs != null) "BLE · dernier envoi à ${time(state.lastSentMs)}" else state.status
        relayButton.text = if (state.running) "Mettre le relais en pause" else "Activer le relais"
        pcSummary.text = preferences.getString(RelayService.KEY_ADDRESS, null) ?: "Aucun ordinateur configuré"
        autoStartSummary.text = if (preferences.getBoolean(RelayService.KEY_ENABLED, false)) "Activée · après déverrouillage du téléphone" else "En pause avec le relais"
        val f = fitbit.state
        val reading = f.selected
        fitbitTitle.text = reading?.model ?: "Votre Fitbit"
        fitbitBody.visibility = if (reading == null) View.GONE else View.VISIBLE
        val fresh = reading?.isFresh(System.currentTimeMillis()) == true
        fitbitGauge.setBattery(reading?.percent, if (!fresh) MUTED else if ((reading.percent ?: 100) < 20) RED else MAUVE)
        fitbitSync.text = reading?.lastSyncMs?.let { "Synchronisé ${relative(it)}\n${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(it))}" } ?: "Date non fournie"
        fitbitStatus.text = if (reading != null && !fresh && !f.busy) "Ancienne mesure. Synchronisez le bracelet dans Google Health. État de charge non fourni." else f.status + if (reading != null) " État de charge non fourni." else ""
        fitbitRefresh.visibility = if (reading != null && !f.consentNeeded) View.VISIBLE else View.GONE
        fitbitRefresh.isEnabled = !f.busy; fitbitRefresh.alpha = if (f.busy) .4f else 1f
        fitbitAction.visibility = if (reading == null || f.consentNeeded) View.VISIBLE else View.GONE
        fitbitAction.isEnabled = !f.busy
        fitbitAction.text = when { f.busy -> "Connexion en cours…"; f.revocationFailed -> "Gérer l’accès Google"; f.consentNeeded -> "Autoriser Google"; f.enabled -> "Actualiser les appareils"; else -> "Associer mon Fitbit" }
        fitbitChoose.visibility = if (f.devices.size > 1 || f.devices.isNotEmpty() && reading == null) View.VISIBLE else View.GONE
        fitbitChoose.isEnabled = !f.busy
        googleDisconnect.visibility = if (f.enabled || f.busy || f.revocationFailed) View.VISIBLE else View.GONE
        googleDisconnect.text = if (f.revocationFailed) "Réessayer le retrait de l’accès" else "Dissocier le Fitbit"
        googleDisconnect.isEnabled = !f.busy
    }

    private fun showPage(settingsPage: Boolean) {
        showingSettings = settingsPage
        backToHome.isEnabled = settingsPage
        home.visibility = if (settingsPage) View.GONE else View.VISIBLE
        settings.visibility = if (settingsPage) View.VISIBLE else View.GONE
        toolbarTitle.text = if (settingsPage) "Réglages" else getString(R.string.app_name)
        toolbarAction.setImageDrawable(RelayGlyph(if (settingsPage) "back" else "settings", TEXT))
        toolbarAction.contentDescription = if (settingsPage) "Retour à l’accueil" else "Ouvrir les réglages"
        toolbar.removeAllViews()
        if (settingsPage) {
            toolbar.addView(toolbarAction)
            toolbar.addView(toolbarTitle, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(16) })
        } else {
            toolbar.addView(toolbarLogo)
            toolbar.addView(toolbarTitle, LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = dp(12) })
            toolbar.addView(toolbarAction)
        }
    }
    override fun onSaveInstanceState(outState: Bundle) { outState.putBoolean("settings", showingSettings); super.onSaveInstanceState(outState) }
    override fun onStart() {
        super.onStart()
        bound = bindService(Intent(this, RelayService::class.java), connection, Context.BIND_AUTO_CREATE)
        fitbit.observe(fitbitObserver); handler.post(refreshLabels)
    }
    override fun onStop() {
        handler.removeCallbacks(refreshLabels); fitbit.removeObserver(fitbitObserver)
        relay?.removeObserver(relayObserver); relay = null
        if (bound) { unbindService(connection); bound = false }
        super.onStop()
    }

    private fun connectFitbit() {
        AlertDialog.Builder(this).setTitle("Associer votre Fitbit")
            .setMessage("BLE lira uniquement vos appareils associés et leur batterie via Google Health, avec Internet. Aucun accès au sommeil, à l’activité ou au rythme cardiaque.\n\nLa configuration Google Cloud se trouve dans Réglages → Accès Google. Le pourcentage du bracelet dépend de sa dernière synchronisation ; son état de charge n’est pas fourni.")
            .setNegativeButton("Annuler", null).setPositiveButton("Continuer") { _, _ ->
                fitbit.connect { pending ->
                    if (isFinishing || isDestroyed) fitbit.authorizationLaunchFailed()
                    else googleAuthorization.launch(IntentSenderRequest.Builder(pending).build())
                }
            }.show()
    }
    private fun chooseFitbit() {
        val devices = fitbit.state.devices
        AlertDialog.Builder(this).setTitle("Votre bracelet")
            .setItems(devices.map { "${it.model} · ${it.percent?.let { p -> "$p %" } ?: "niveau inconnu"}" }.toTypedArray()) { _, index -> fitbit.select(devices[index].id) }
            .setNegativeButton("Annuler", null).show()
    }
    private fun googleSetup() {
        val signatures = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo?.apkContentsSigners
        val sha1 = signatures?.firstOrNull()?.let { signature -> MessageDigest.getInstance("SHA-1").digest(signature.toByteArray()).joinToString(":") { "%02X".format(it) } } ?: "Indisponible"
        val details = "Application Android : $packageName\nSHA-1 : $sha1\nAutorisation : ${GoogleHealthApi.SCOPE}"
        AlertDialog.Builder(this).setTitle("Accès Google · configuration initiale")
            .setMessage("Dans votre projet Google Cloud : activez Google Health API, configurez l’écran de consentement, ajoutez votre compte Google Health aux utilisateurs testeurs, puis créez un client OAuth Android avec les valeurs ci-dessous.\n\n$details\n\nAucun secret client n’est nécessaire dans l’application. Revenez ensuite à l’accueil pour associer votre Fitbit.")
            .setNegativeButton("Fermer", null).setNeutralButton("Copier les valeurs") { _, _ -> copy("Configuration Google", details) }
            .setPositiveButton("Google Cloud") { _, _ -> startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://console.cloud.google.com/auth/clients"))) }.show()
    }
    private fun configurePc(startAfterSave: Boolean = false) {
        if (lastRelay.running) {
            info("Ordinateur enregistré", "${preferences.getString(RelayService.KEY_ADDRESS, "")}\n\nLe relais est actif. Mettez-le en pause depuis l’accueil avant de modifier cette adresse. Aucun changement n’est nécessaire pour une utilisation quotidienne.")
            return
        }
        val input = EditText(this).apply {
            setSingleLine(); inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
            hint = "AA:BB:CC:DD:EE:FF"; typeface = Typeface.MONOSPACE
            setText(preferences.getString(RelayService.KEY_ADDRESS, "")); setPadding(dp(24), dp(16), dp(24), dp(16))
        }
        val dialog = AlertDialog.Builder(this).setTitle("Adresse Bluetooth du PC")
            .setMessage("À renseigner une seule fois. Aucun appairage système n’est nécessaire.")
            .setView(input).setNegativeButton("Annuler", null).setPositiveButton("Enregistrer", null).create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val address = input.text.toString().trim().uppercase(Locale.ROOT)
                if (!BluetoothAdapter.checkBluetoothAddress(address)) input.error = "Format attendu : AA:BB:CC:DD:EE:FF"
                else {
                    preferences.edit().putString(RelayService.KEY_ADDRESS, address).apply(); dialog.dismiss(); render()
                    if (startAfterSave) startRelay(address)
                }
            }
        }
        dialog.show()
    }
    private fun withPermissions(action: () -> Unit) {
        val required = listOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
        val missing = required.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) action() else { afterPermission = action; bluetoothAuthorization.launch(missing.toTypedArray()) }
    }
    private fun startRelay(address: String) {
        try {
            startForegroundService(Intent(this, RelayService::class.java).setAction(RelayService.ACTION_START).putExtra(RelayService.EXTRA_ADDRESS, address))
        } catch (_: ForegroundServiceStartNotAllowedException) { info("Démarrage bloqué", "Revenez dans l’application pour activer le relais.") }
        catch (_: SecurityException) { info("Autorisation nécessaire", "Autorisez les appareils à proximité dans les paramètres Android.") }
    }
    private fun info(title: String, message: String) { AlertDialog.Builder(this).setTitle(title).setMessage(message).setPositiveButton("Compris", null).show() }
    private fun copy(label: String, value: String) {
        getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(label, value))
        if (Build.VERSION.SDK_INT < 33) Toast.makeText(this, "Copié", Toast.LENGTH_SHORT).show()
    }
    private fun time(ms: Long) = android.text.format.DateFormat.getTimeFormat(this).format(Date(ms))
    private fun relative(ms: Long): String {
        val minutes = ((System.currentTimeMillis() - ms).coerceAtLeast(0) / 60_000)
        return when { minutes == 0L -> "à l’instant"; minutes < 60 -> "il y a $minutes min"; minutes < 1440 -> "il y a ${minutes / 60} h"; else -> "il y a ${minutes / 1440} j" }
    }
}
