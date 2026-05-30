package com.musestructnative

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

class PlaybackModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

  private var receiverRegistered = false
  private val statusReceiver =
      object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
          emitStatus(PlaybackStatusSnapshot.fromBundle(intent?.extras))
        }
      }
  private val commandReceiver =
      object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
          val command = intent?.getStringExtra(PlaybackService.EXTRA_COMMAND) ?: return
          emitCommand(command)
        }
      }

  init {
    registerStatusReceiver()
  }

  override fun getName(): String = "PlaybackModule"

  override fun invalidate() {
    unregisterStatusReceiver()
    super.invalidate()
  }

  @ReactMethod
  fun addListener(eventName: String) = Unit

  @ReactMethod
  fun removeListeners(count: Int) = Unit

  @ReactMethod
  fun getStatus(promise: Promise) {
    promise.resolve(snapshotToMap(PlaybackService.latestStatus()))
  }

  @ReactMethod
  fun load(track: ReadableMap, promise: Promise) {
    if (!isTrackPlayable(track)) {
      promise.reject("E_INVALID_TRACK", "The track is missing a playable URL.")
      return
    }

    val intent =
        Intent(reactApplicationContext, PlaybackService::class.java).apply {
          action = PlaybackService.ACTION_LOAD
          putTrackExtras(track)
        }

    ContextCompat.startForegroundService(reactApplicationContext, intent)
    promise.resolve(snapshotToMap(PlaybackService.latestStatus()))
  }

  @ReactMethod
  fun loadFromQueue(track: ReadableMap, promise: Promise) {
    if (!isTrackPlayable(track)) {
      promise.reject("E_INVALID_TRACK", "The track is missing a playable URL.")
      return
    }

    val intent =
        Intent(reactApplicationContext, PlaybackService::class.java).apply {
          action = PlaybackService.ACTION_LOAD
          putExtra(PlaybackService.EXTRA_PRESERVE_QUEUE, true)
          putTrackExtras(track)
        }

    ContextCompat.startForegroundService(reactApplicationContext, intent)
    promise.resolve(snapshotToMap(PlaybackService.latestStatus()))
  }

  @ReactMethod
  fun loadQueue(tracks: ReadableArray, startIndex: Int, promise: Promise) {
    val queueBundles = arrayListOf<android.os.Bundle>()
    for (index in 0 until tracks.size()) {
      val track = tracks.getMap(index) ?: continue
      if (!isTrackPlayable(track)) {
        promise.reject("E_INVALID_TRACK", "The queue contains a track without a playable URL.")
        return
      }
      queueBundles.add(trackToBundle(track))
    }

    if (queueBundles.isEmpty()) {
      promise.reject("E_INVALID_QUEUE", "The queue does not contain any playable tracks.")
      return
    }

    val clampedIndex = startIndex.coerceIn(0, queueBundles.lastIndex)
    val intent =
        Intent(reactApplicationContext, PlaybackService::class.java).apply {
          action = PlaybackService.ACTION_LOAD_QUEUE
          putParcelableArrayListExtra(PlaybackService.EXTRA_QUEUE_TRACKS, queueBundles)
          putExtra(PlaybackService.EXTRA_QUEUE_INDEX, clampedIndex)
        }

    ContextCompat.startForegroundService(reactApplicationContext, intent)
    promise.resolve(snapshotToMap(PlaybackService.latestStatus()))
  }

  @ReactMethod
  fun pause(promise: Promise) {
    sendServiceIntent(PlaybackService.ACTION_PAUSE)
    promise.resolve(null)
  }

  @ReactMethod
  fun play(promise: Promise) {
    sendServiceIntent(PlaybackService.ACTION_PLAY, startForeground = true)
    promise.resolve(null)
  }

  @ReactMethod
  fun seekTo(position: Double, promise: Promise) {
    sendServiceIntent(PlaybackService.ACTION_SEEK) {
      putExtra(PlaybackService.EXTRA_POSITION, position)
    }
    promise.resolve(null)
  }

  @ReactMethod
  fun stop(promise: Promise) {
    sendServiceIntent(PlaybackService.ACTION_STOP)
    promise.resolve(null)
  }

  private fun emitStatus(snapshot: PlaybackStatusSnapshot) {
    reactContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(EVENT_STATUS_CHANGED, snapshotToMap(snapshot))
  }

  private fun emitCommand(command: String) {
    reactContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(EVENT_COMMAND_CHANGED, command)
  }

  private fun optionalString(map: ReadableMap, key: String): String? {
    return if (!map.hasKey(key) || map.isNull(key)) {
      null
    } else {
      map.getString(key)
    }
  }

  private fun isTrackPlayable(track: ReadableMap): Boolean {
    val trackUrl = optionalString(track, "url")
    val trackSource = optionalString(track, "source")
    return trackSource == "tidal" || !trackUrl.isNullOrBlank()
  }

  private fun Intent.putTrackExtras(track: ReadableMap) {
    putExtra(PlaybackService.EXTRA_TRACK_ID, optionalString(track, "id"))
    putExtra(PlaybackService.EXTRA_TRACK_KEY, optionalString(track, "key"))
    putExtra(PlaybackService.EXTRA_TRACK_TITLE, optionalString(track, "title"))
    putExtra(PlaybackService.EXTRA_TRACK_ARTIST, optionalString(track, "artist"))
    putExtra(PlaybackService.EXTRA_TRACK_ALBUM, optionalString(track, "album"))
    putExtra(PlaybackService.EXTRA_TRACK_ARTWORK_URL, optionalString(track, "artworkUrl"))
    putExtra(PlaybackService.EXTRA_TRACK_DESCRIPTION, optionalString(track, "description"))
    putExtra(PlaybackService.EXTRA_TRACK_SOURCE, optionalString(track, "source"))
    putExtra(PlaybackService.EXTRA_TRACK_URL, optionalString(track, "url"))
    putExtra(PlaybackService.EXTRA_TRACK_BACKEND_URL, optionalString(track, "backendUrl"))
    putExtra(PlaybackService.EXTRA_TRACK_SESSION_TOKEN, optionalString(track, "sessionToken"))
  }

  private fun trackToBundle(track: ReadableMap) =
      android.os.Bundle().apply {
        putString("id", optionalString(track, "id"))
        putString("key", optionalString(track, "key"))
        putString("title", optionalString(track, "title"))
        putString("artist", optionalString(track, "artist"))
        putString("album", optionalString(track, "album"))
        putString("artworkUrl", optionalString(track, "artworkUrl"))
        putString("description", optionalString(track, "description"))
        putString("backendUrl", optionalString(track, "backendUrl"))
        putString("sessionToken", optionalString(track, "sessionToken"))
        putString("source", optionalString(track, "source"))
        putString("url", optionalString(track, "url"))
      }

  private fun registerStatusReceiver() {
    if (receiverRegistered) {
      return
    }

    val statusFilter = IntentFilter(PlaybackService.ACTION_STATUS_CHANGED)
    val commandFilter = IntentFilter(PlaybackService.ACTION_COMMAND_CHANGED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      reactContext.registerReceiver(statusReceiver, statusFilter, Context.RECEIVER_NOT_EXPORTED)
      reactContext.registerReceiver(commandReceiver, commandFilter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("DEPRECATION")
      reactContext.registerReceiver(statusReceiver, statusFilter)
      reactContext.registerReceiver(commandReceiver, commandFilter)
    }
    receiverRegistered = true
  }

  private fun sendServiceIntent(
      action: String,
      startForeground: Boolean = false,
      configure: Intent.() -> Unit = {}
  ) {
    val intent =
        Intent(reactApplicationContext, PlaybackService::class.java).apply {
          this.action = action
          configure()
        }

    if (startForeground) {
      ContextCompat.startForegroundService(reactApplicationContext, intent)
    } else {
      reactApplicationContext.startService(intent)
    }
  }

  private fun snapshotToMap(snapshot: PlaybackStatusSnapshot) =
      Arguments.createMap().apply {
        putBoolean("hasTrack", snapshot.hasTrack)
        putBoolean("isPlaying", snapshot.isPlaying)
        putBoolean("isBuffering", snapshot.isBuffering)
        putDouble("position", snapshot.position)
        putDouble("duration", snapshot.duration)
        putString("errorMessage", snapshot.errorMessage)
        putMap(
            "track",
            snapshot.track?.let { track ->
              Arguments.createMap().apply {
                putString("id", track.id)
                putString("key", track.key)
                putString("title", track.title)
                putString("artist", track.artist)
                putString("album", track.album)
                putString("artworkUrl", track.artworkUrl)
                putString("description", track.description)
                putString("source", track.source)
                putString("url", track.url)
              }
            })
      }

  private fun unregisterStatusReceiver() {
    if (!receiverRegistered) {
      return
    }

    reactContext.unregisterReceiver(statusReceiver)
    reactContext.unregisterReceiver(commandReceiver)
    receiverRegistered = false
  }

  companion object {
    const val EVENT_COMMAND_CHANGED = "PlaybackCommand"
    const val EVENT_STATUS_CHANGED = "PlaybackStatus"
  }
}