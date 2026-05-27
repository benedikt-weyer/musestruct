package com.musestructnative

import android.app.Application
import com.tidal.sdk.auth.CredentialsProvider
import com.tidal.sdk.auth.model.AuthResult
import com.tidal.sdk.auth.model.Credentials
import com.tidal.sdk.auth.model.CredentialsUpdatedMessage
import com.tidal.sdk.common.TidalMessage
import com.tidal.sdk.eventproducer.EventSender
import com.tidal.sdk.eventproducer.model.ConsentCategory
import com.tidal.sdk.player.Player
import com.tidal.sdk.player.common.model.MediaProduct
import com.tidal.sdk.player.common.model.ApiError
import com.tidal.sdk.player.common.model.ProductType
import com.tidal.sdk.player.playbackengine.model.Event
import android.util.Log
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

internal data class TidalPlaybackSnapshot(
    val durationSeconds: Double = 0.0,
    val errorMessage: String? = null,
    val isBuffering: Boolean = false,
    val isPlaying: Boolean = false,
    val playbackStateName: String = "IDLE",
    val positionSeconds: Double = 0.0,
)

internal class TidalPlaybackSession(
    application: Application,
    track: PlaybackTrack,
    private val onCompletion: () -> Unit,
    private val onError: (String) -> Unit,
    private val onSnapshot: (TidalPlaybackSnapshot) -> Unit,
) {
  private val credentialsProvider =
      BackendTidalCredentialsProvider(
          backendUrl = track.backendUrl,
          sessionToken = track.sessionToken,
      )
  private val player =
      Player(
          application = application,
          credentialsProvider = credentialsProvider,
          eventSender = NoOpEventSender(),
          version = "musestruct-react-native",
      )
  private val playbackEngine = player.playbackEngine
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

  init {
    scope.launch {
      playbackEngine.events.collect { event ->
        when (event) {
          is Event.Error -> {
            Log.e(TAG, "Tidal playback error code=${event.errorCode}", event)
            onError(event.toReadableMessage())
          }
          is Event.MediaProductEnded -> {
            onSnapshot(snapshot())
            onCompletion()
          }
          else -> onSnapshot(snapshot())
        }
      }
    }
  }

  fun load(track: PlaybackTrack) {
    val productId = track.id?.takeIf { it.isNotBlank() }
        ?: throw IllegalArgumentException("The track is missing a Tidal product id.")
    playbackEngine.load(
        MediaProduct(
            productType = ProductType.TRACK,
            productId = productId,
            sourceType = track.source,
            sourceId = track.key,
            referenceId = track.key,
        )
    )
    playbackEngine.play()
    onSnapshot(snapshot())
  }

  fun pause() {
    playbackEngine.pause()
    onSnapshot(snapshot())
  }

  fun play() {
    playbackEngine.play()
    onSnapshot(snapshot())
  }

  fun release() {
    scope.cancel()
    playbackEngine.release()
    player.release()
  }

  fun seek(positionSeconds: Double) {
    playbackEngine.seek(positionSeconds.toFloat().coerceAtLeast(0f))
    onSnapshot(snapshot())
  }

  fun snapshot(): TidalPlaybackSnapshot {
    val playbackContext = playbackEngine.playbackContext
    val playbackStateName = playbackEngine.playbackState.name
    return TidalPlaybackSnapshot(
        durationSeconds = playbackContext?.duration?.toDouble()?.coerceAtLeast(0.0) ?: 0.0,
        isBuffering =
            playbackStateName.contains("BUFFER", ignoreCase = true) ||
                playbackStateName.contains("STALL", ignoreCase = true) ||
                playbackStateName.contains("LOAD", ignoreCase = true),
        isPlaying = playbackStateName == "PLAYING",
        playbackStateName = playbackStateName,
        positionSeconds = playbackEngine.assetPosition.toDouble().coerceAtLeast(0.0),
    )
  }
}

private data class BackendTidalCredentials(
    val accessToken: String,
    val clientId: String,
    val clientUniqueKey: String?,
  val expiresAtEpochMs: Long?,
    val grantedScopes: Set<String>,
    val requestedScopes: Set<String>,
    val userId: String?,
)

private class BackendTidalCredentialsProvider(
    private val backendUrl: String?,
    private val sessionToken: String?,
) : CredentialsProvider {
  private val messageBus = MutableSharedFlow<TidalMessage>(replay = 1, extraBufferCapacity = 1)
  override val bus: Flow<TidalMessage> = messageBus.asSharedFlow()

  @Volatile private var cachedCredentials: Credentials? = null

  override suspend fun getCredentials(apiErrorSubStatus: String?): AuthResult<Credentials> {
    return try {
      val credentials = fetchCredentials(forceRefresh = !apiErrorSubStatus.isNullOrBlank())
      cachedCredentials = credentials
      messageBus.tryEmit(CredentialsUpdatedMessage(credentials))
      AuthResult.Success(credentials)
    } catch (_: Exception) {
      AuthResult.Failure(null)
    }
  }

  override fun isUserLoggedIn(): Boolean {
    return !backendUrl.isNullOrBlank() && !sessionToken.isNullOrBlank()
  }

  private suspend fun fetchCredentials(forceRefresh: Boolean): Credentials {
    if (!forceRefresh) {
      cachedCredentials?.let { currentCredentials ->
      val expiresAt = currentCredentials.expires
      if (expiresAt == null || expiresAt > System.currentTimeMillis() + 30_000L) {
        return currentCredentials
      }
      }
    }

    val response = withContext(Dispatchers.IO) {
      val normalizedBackendUrl = backendUrl?.trimEnd('/')
          ?: throw IllegalStateException("The backend URL is missing for Tidal playback.")
      val authToken = sessionToken
          ?: throw IllegalStateException("The session token is missing for Tidal playback.")
      val connection =
          (URL("$normalizedBackendUrl/api/streaming/tidal/sdk-credentials").openConnection()
                  as HttpURLConnection)
              .apply {
                requestMethod = "GET"
                connectTimeout = 15_000
                readTimeout = 15_000
                setRequestProperty("Authorization", "Bearer $authToken")
                setRequestProperty("Accept", "application/json")
              }

      try {
        val body =
            (if (connection.responseCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()
                ?.use(BufferedReader::readText)
                .orEmpty()
        if (connection.responseCode !in 200..299) {
          throw IllegalStateException(body.ifBlank { "Failed to load Tidal SDK credentials." })
        }
        body
      } finally {
        connection.disconnect()
      }
    }

    return parseCredentials(response)
  }

  private fun parseCredentials(payload: String): Credentials {
    val root = JSONObject(payload)
    if (!root.optBoolean("success", false)) {
      throw IllegalStateException(root.optString("message", "Failed to load Tidal credentials."))
    }

    val data = root.optJSONObject("data")
        ?: throw IllegalStateException("Tidal credentials were missing from the backend response.")
    val backendCredentials = BackendTidalCredentials(
        accessToken = data.getString("access_token"),
        clientId = data.getString("client_id"),
        clientUniqueKey = data.optString("client_unique_key").takeIf { it.isNotBlank() },
      expiresAtEpochMs =
        data.optString("expires_at").takeIf { it.isNotBlank() }?.let(Instant::parse)?.toEpochMilli(),
        grantedScopes = jsonArrayToSet(data.optJSONArray("granted_scopes")),
        requestedScopes = jsonArrayToSet(data.optJSONArray("requested_scopes")),
        userId = data.optString("user_id").takeIf { it.isNotBlank() },
    )

    return Credentials(
        clientId = backendCredentials.clientId,
        requestedScopes = backendCredentials.requestedScopes,
        clientUniqueKey = backendCredentials.clientUniqueKey,
        grantedScopes = backendCredentials.grantedScopes,
        userId = backendCredentials.userId,
        expires = backendCredentials.expiresAtEpochMs,
        token = backendCredentials.accessToken,
    )
  }

  private fun jsonArrayToSet(array: JSONArray?): Set<String> {
    if (array == null) {
      return emptySet()
    }

    return buildSet {
      for (index in 0 until array.length()) {
        val value = array.optString(index)
        if (value.isNotBlank()) {
          add(value)
        }
      }
    }
  }
}

private class NoOpEventSender : EventSender {
  override fun sendEvent(
      eventName: String,
      consentCategory: ConsentCategory,
      payload: String,
      headers: Map<String, String>,
  ) = Unit

  override fun setBlockedConsentCategories(blockedConsentCategories: Set<ConsentCategory>) = Unit
}

private fun Event.Error.toReadableMessage(): String {
  val apiError = cause as? ApiError
  val apiMessage = apiError?.userMessage?.takeIf { it.isNotBlank() }
  val subStatus = apiError?.subStatus?.toString()?.takeIf { it.isNotBlank() }
  val message = this.message?.takeIf { it.isNotBlank() }

  return when {
    apiMessage != null -> apiMessage
    subStatus != null -> "Tidal playback failed ($subStatus). Please reconnect Tidal and try again."
    message != null -> message
    else -> "This track could not be played."
  }
}

private const val TAG = "TidalSdkPlayback"