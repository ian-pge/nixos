package dev.ian.ble

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.api.identity.RevokeAccessRequest
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import java.util.concurrent.Executors
import java.util.concurrent.Future

data class FitbitState(
    val enabled: Boolean = false,
    val busy: Boolean = false,
    val consentNeeded: Boolean = false,
    val revocationFailed: Boolean = false,
    val status: String = "Associez votre Fitbit pour retrouver sa batterie ici et sur le PC.",
    val devices: List<FitbitReading> = emptyList(),
    val selected: FitbitReading? = null,
)

/** App-scoped, optional provider. Tokens stay inside Google Play services/in memory. */
class FitbitRepository private constructor(context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val preferences = context.getSharedPreferences("fitbit", Context.MODE_PRIVATE)
    private val client by lazy { Identity.getAuthorizationClient(context) }
    private val scopes = listOf(Scope(GoogleHealthApi.SCOPE))
    private val executor = Executors.newSingleThreadExecutor()
    private val observers = mutableSetOf<(FitbitState) -> Unit>()
    private var worker: Future<*>? = null
    private var generation = 0
    private var relayActive = false
    private var waitingForConsent = false
    private var revoking = false
    private val poll = Runnable { refresh() }
    private var revokeTimeout: Runnable? = null
    private val timeout = Runnable {
        cancelWork()
        publish(state.copy(busy = false, status = "Google ne répond pas. Réessayez dans un instant."))
        schedule()
    }
    var state = FitbitState(enabled = preferences.getBoolean("enabled", false)).let {
        if (preferences.getBoolean("revoke_pending", false)) it.copy(revocationFailed = true,
            status = "Fitbit désactivé. Terminez le retrait de l’accès Google depuis les réglages.") else it
    }
        private set

    fun observe(observer: (FitbitState) -> Unit) { observers.add(observer); observer(state) }
    fun removeObserver(observer: (FitbitState) -> Unit) { observers.remove(observer) }

    fun setRelayActive(active: Boolean) {
        if (relayActive == active) return
        relayActive = active
        handler.removeCallbacks(poll)
        // No periodic cloud access when the user has stopped the relay.
        if (active && state.enabled && !state.busy && !waitingForConsent) refresh()
    }

    fun connect(launchConsent: (PendingIntent) -> Unit) {
        if (state.busy || revoking || waitingForConsent || state.revocationFailed) return
        cancelWork()
        publish(state.copy(busy = true, status = "Connexion à Google…"))
        authorize(generation, launchConsent, retry401 = true)
    }

    fun refresh() {
        if (!state.enabled || state.busy || waitingForConsent || revoking) return
        cancelWork()
        publish(state.copy(busy = true, status = "Actualisation depuis Google Health…"))
        authorize(generation, null, retry401 = true)
    }

    private fun authorize(epoch: Int, launch: ((PendingIntent) -> Unit)?, retry401: Boolean) {
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, 45_000L)
        client.authorize(AuthorizationRequest.builder().setRequestedScopes(scopes).build())
            .addOnSuccessListener { result ->
                if (epoch != generation) return@addOnSuccessListener
                if (result.hasResolution()) {
                    Log.d("BLEAuth", "resolution_required interactive=${launch != null}")
                    handler.removeCallbacks(timeout)
                    publish(state.copy(busy = false, consentNeeded = true, selected = null, devices = emptyList(),
                        status = "Autorisez l’accès aux appareils dans la fenêtre Google."))
                    if (launch != null && result.pendingIntent != null) {
                        waitingForConsent = true
                        launch(result.pendingIntent!!)
                    }
                    // A background task must never open a consent screen by itself.
                } else acceptAuthorization(result, epoch, retry401)
            }
            .addOnFailureListener { error -> if (epoch == generation) fail(error) }
    }

    fun authorizationLaunchFailed() {
        if (!waitingForConsent) return
        waitingForConsent = false
        handler.removeCallbacks(timeout)
        Log.w("BLEAuth", "authorization_window_launch_failed")
        publish(state.copy(busy = false, consentNeeded = true,
            status = "Impossible d’ouvrir la fenêtre Google. Revenez dans l’application puis réessayez."))
    }

    fun completeAuthorization(data: Intent?, resultCode: Int) {
        if (!waitingForConsent) return
        waitingForConsent = false
        Log.d("BLEAuth", "activity_result code=$resultCode dataPresent=${data != null}")
        if (data == null) {
            // An empty result may mean user dismissal, a blocked flow or a
            // system interruption. It is not evidence of a voluntary cancel.
            handler.removeCallbacks(timeout)
            publish(state.copy(busy = false, consentNeeded = true,
                status = "La fenêtre Google s’est fermée sans résultat d’autorisation (retour $resultCode). Réessayez ; si cela se répète, vérifiez la configuration Google."))
            return
        }
        val result = try { client.getAuthorizationResultFromIntent(data) }
        catch (error: ApiException) { fail(error); return }
        catch (error: RuntimeException) {
            handler.removeCallbacks(timeout)
            Log.w("BLEAuth", "invalid_sdk_result type=${error.javaClass.simpleName}")
            publish(state.copy(busy = false, consentNeeded = true, status = "Réponse Google illisible. Réessayez l’autorisation."))
            return
        }
        acceptAuthorization(result, generation, retry401 = true)
    }

    private fun acceptAuthorization(result: AuthorizationResult, epoch: Int, retry401: Boolean) {
        val token = result.accessToken
        if (!result.grantedScopes.contains(GoogleHealthApi.SCOPE) || token.isNullOrBlank()) {
            Log.w("BLEAuth", "requested_scope_or_access_token_missing")
            handler.removeCallbacks(timeout)
            publish(state.copy(busy = false, consentNeeded = true, selected = null, devices = emptyList(),
                status = "L’accès aux paramètres Google Health n’a pas été accordé."))
            return
        }
        preferences.edit().putBoolean("enabled", true).apply()
        Log.d("BLEAuth", "requested_scope_authorized")
        publish(state.copy(enabled = true, busy = true, consentNeeded = false, status = "Lecture de vos appareils…"))
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, 45_000L)
        worker = executor.submit {
            val resultData = runCatching { GoogleHealthApi().devices(token) }
            handler.post {
                if (epoch != generation) return@post
                handler.removeCallbacks(timeout)
                val error = resultData.exceptionOrNull()
                if (error is GoogleHealthApi.Failure && error.status == 401 && retry401) {
                    // One bounded refresh after rejection; no token is persisted or logged.
                    handler.postDelayed(timeout, 45_000L)
                    client.clearToken(ClearTokenRequest.builder().setToken(token).build())
                        .addOnCompleteListener { if (epoch == generation) authorize(epoch, null, retry401 = false) }
                    return@post
                }
                if (error != null) { fail(error); return@post }
                val devices = resultData.getOrThrow()
                val selected = FitbitReading.select(devices, preferences.getString("device_id", null))
                if (selected != null) preferences.edit().putString("device_id", selected.id).apply()
                publish(state.copy(busy = false, consentNeeded = false, devices = devices, selected = selected,
                    status = when {
                        devices.isEmpty() -> "Aucun bracelet trouvé. Synchronisez votre Fitbit dans Google Health."
                        selected == null -> "Choisissez le bracelet à afficher."
                        selected.lastSyncMs == null -> "Google ne fournit pas de date de synchronisation."
                        !selected.isFresh(System.currentTimeMillis()) -> "Ancienne mesure — synchronisez le bracelet dans Google Health."
                        selected.percent == null -> "Le niveau de batterie n’est pas fourni par Google."
                        else -> "Batterie issue de la dernière synchronisation Google Health."
                    }))
                schedule()
            }
        }
    }

    fun select(id: String) {
        val selected = state.devices.singleOrNull { it.id == id } ?: return
        preferences.edit().putString("device_id", id).apply()
        publish(state.copy(selected = selected, status = "Bracelet sélectionné. Mesure issue de Google Health."))
    }

    fun disconnect() {
        if (revoking) return
        cancelWork()
        waitingForConsent = false
        preferences.edit().clear().putBoolean("revoke_pending", true).apply()
        revoking = true
        publish(FitbitState(busy = true, status = "Retrait de l’accès Google…"))
        val epoch = generation
        revokeTimeout = Runnable { finishRevocation(epoch, false) }.also { handler.postDelayed(it, 45_000L) }
        client.revokeAccess(RevokeAccessRequest.builder().setScopes(scopes).build()).addOnCompleteListener { task ->
            finishRevocation(epoch, task.isSuccessful)
        }
    }

    private fun finishRevocation(epoch: Int, success: Boolean) {
        if (epoch != generation || !revoking) return
        revokeTimeout?.let { handler.removeCallbacks(it) }; revokeTimeout = null
        generation++ // An overdue callback cannot overwrite a subsequent authorization.
        revoking = false
        if (success) preferences.edit().remove("revoke_pending").apply()
        publish(FitbitState(revocationFailed = !success, status = if (success) "Fitbit dissocié. Données locales effacées."
            else "Fitbit désactivé. Le retrait de l’accès a échoué : réessayez depuis les réglages ou votre compte Google."))
    }

    private fun fail(error: Throwable) {
        handler.removeCallbacks(timeout)
        // Diagnostic categories only: never log the Intent, exception message,
        // account, HTTP body, auth code or token returned by Google.
        Log.w("BLEAuth", when (error) {
            is ApiException -> "sdk_failure code=${error.statusCode}"
            is GoogleHealthApi.Failure -> "http_failure status=${error.status} reason=${error.reason}"
            else -> "request_failed type=${error.javaClass.simpleName}"
        })
        val apiConsentRequired = error is GoogleHealthApi.Failure && (error.status == 401 || error.reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT")
        val needsConsent = error is ApiException && (state.consentNeeded || error.statusCode == 10 || error.statusCode == 16)
            || apiConsentRequired
        val message = when {
            error is ApiException && error.statusCode == 10 -> "Configuration OAuth Android invalide (code 10). Vérifiez le package et le SHA-1 dans Google Cloud → Clients."
            error is ApiException && error.statusCode == 16 -> "Google a interrompu l’autorisation (code 16). Aucun accès n’a été confirmé ; réessayez."
            error is GoogleHealthApi.Failure && error.reason == "ACCOUNT_NOT_LINKED" -> "Connectez ce compte dans Google Health avant de réessayer."
            error is GoogleHealthApi.Failure && error.reason == "SERVICE_DISABLED" -> "Activez Google Health API dans le projet Google Cloud."
            apiConsentRequired -> "Autorisation Google expirée ou retirée. Reconnectez votre Fitbit."
            error is GoogleHealthApi.Failure && error.status == 403 -> "Accès Google refusé. Vérifiez le compte testeur et l’autorisation dans Google Cloud."
            error is GoogleHealthApi.Failure && error.status == 429 -> "Google limite les requêtes. Nouvelle tentative dans 15 minutes."
            error is ApiException -> "Connexion Google indisponible (code ${error.statusCode}). Vérifiez Internet et la configuration Google Cloud."
            else -> "Actualisation impossible. Vérifiez Internet ; la dernière mesure conserve sa date."
        }
        val removeData = needsConsent || error is GoogleHealthApi.Failure && error.status in listOf(400, 403)
        publish(state.copy(busy = false, consentNeeded = needsConsent, status = message,
            selected = if (removeData) null else state.selected, devices = if (removeData) emptyList() else state.devices))
        schedule()
    }

    private fun schedule() {
        handler.removeCallbacks(poll)
        if (relayActive && state.enabled && !state.consentNeeded && !waitingForConsent && !revoking)
            handler.postDelayed(poll, POLL_MS)
    }
    private fun cancelWork() {
        generation++
        worker?.cancel(true)
        worker = null
        handler.removeCallbacks(poll)
        handler.removeCallbacks(timeout)
    }
    private fun publish(next: FitbitState) { state = next; observers.toList().forEach { it(next) } }

    companion object {
        const val POLL_MS = 15 * 60 * 1000L
        @Volatile private var instance: FitbitRepository? = null
        fun get(context: Context): FitbitRepository = instance ?: synchronized(this) {
            instance ?: FitbitRepository(context.applicationContext).also { instance = it }
        }
    }
}
