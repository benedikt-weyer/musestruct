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
    val trackUrl = optionalString(track, "url")
    if (trackUrl.isNullOrBlank()) {
      promise.reject("E_INVALID_TRACK", "The track is missing a playable URL.")
      return
    }

    val intent =
        Intent(reactApplicationContext, PlaybackService::class.java).apply {
          action = PlaybackService.ACTION_LOAD
          putExtra(PlaybackService.EXTRA_TRACK_ID, optionalString(track, "id"))
          putExtra(PlaybackService.EXTRA_TRACK_KEY, optionalString(track, "key"))
          putExtra(PlaybackService.EXTRA_TRACK_TITLE, optionalString(track, "title"))
          putExtra(PlaybackService.EXTRA_TRACK_ARTIST, optionalString(track, "artist"))
          putExtra(PlaybackService.EXTRA_TRACK_ALBUM, optionalString(track, "album"))
          putExtra(PlaybackService.EXTRA_TRACK_ARTWORK_URL, optionalString(track, "artworkUrl"))
          putExtra(PlaybackService.EXTRA_TRACK_DESCRIPTION, optionalString(track, "description"))
          putExtra(PlaybackService.EXTRA_TRACK_SOURCE, optionalString(track, "source"))
          putExtra(PlaybackService.EXTRA_TRACK_URL, trackUrl)
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

  private fun optionalString(map: ReadableMap, key: String): String? {
    return if (!map.hasKey(key) || map.isNull(key)) {
      null
    } else {
      map.getString(key)
    }
  }

  private fun registerStatusReceiver() {
    if (receiverRegistered) {
      return
    }

    val filter = IntentFilter(PlaybackService.ACTION_STATUS_CHANGED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      reactContext.registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("DEPRECATION")
      reactContext.registerReceiver(statusReceiver, filter)
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
    receiverRegistered = false
  }

  companion object {
    const val EVENT_STATUS_CHANGED = "PlaybackStatus"
  }
}