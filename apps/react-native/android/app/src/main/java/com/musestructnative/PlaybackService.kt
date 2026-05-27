package com.musestructnative

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Looper
import android.os.Handler
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import kotlin.math.roundToInt

internal data class PlaybackTrack(
  val backendUrl: String?,
    val id: String?,
    val key: String?,
    val title: String?,
    val artist: String?,
    val album: String?,
    val artworkUrl: String?,
    val description: String?,
    val sessionToken: String?,
    val source: String?,
    val url: String?,
) {
  fun toBundle(): Bundle =
      Bundle().apply {
        putString("id", id)
        putString("key", key)
        putString("title", title)
        putString("artist", artist)
        putString("album", album)
        putString("artworkUrl", artworkUrl)
        putString("description", description)
        putString("source", source)
        putString("url", url)
      }

  companion object {
    fun fromIntent(intent: Intent): PlaybackTrack =
        PlaybackTrack(
        backendUrl = intent.getStringExtra(PlaybackService.EXTRA_TRACK_BACKEND_URL),
            id = intent.getStringExtra(PlaybackService.EXTRA_TRACK_ID),
            key = intent.getStringExtra(PlaybackService.EXTRA_TRACK_KEY),
            title = intent.getStringExtra(PlaybackService.EXTRA_TRACK_TITLE),
            artist = intent.getStringExtra(PlaybackService.EXTRA_TRACK_ARTIST),
            album = intent.getStringExtra(PlaybackService.EXTRA_TRACK_ALBUM),
            artworkUrl = intent.getStringExtra(PlaybackService.EXTRA_TRACK_ARTWORK_URL),
            description = intent.getStringExtra(PlaybackService.EXTRA_TRACK_DESCRIPTION),
        sessionToken = intent.getStringExtra(PlaybackService.EXTRA_TRACK_SESSION_TOKEN),
            source = intent.getStringExtra(PlaybackService.EXTRA_TRACK_SOURCE),
            url = intent.getStringExtra(PlaybackService.EXTRA_TRACK_URL),
        )

    fun fromBundle(bundle: Bundle?): PlaybackTrack? {
      if (bundle == null) {
        return null
      }

      return PlaybackTrack(
          backendUrl = null,
          id = bundle.getString("id"),
          key = bundle.getString("key"),
          title = bundle.getString("title"),
          artist = bundle.getString("artist"),
          album = bundle.getString("album"),
          artworkUrl = bundle.getString("artworkUrl"),
          description = bundle.getString("description"),
          sessionToken = null,
          source = bundle.getString("source"),
          url = bundle.getString("url"),
      )
    }
  }
}

internal data class PlaybackStatusSnapshot(
    val hasTrack: Boolean = false,
    val track: PlaybackTrack? = null,
    val isPlaying: Boolean = false,
    val isBuffering: Boolean = false,
    val position: Double = 0.0,
    val duration: Double = 0.0,
    val errorMessage: String? = null,
) {
  fun toBundle(): Bundle =
      Bundle().apply {
        putBoolean("hasTrack", hasTrack)
        putBundle("track", track?.toBundle())
        putBoolean("isPlaying", isPlaying)
        putBoolean("isBuffering", isBuffering)
        putDouble("position", position)
        putDouble("duration", duration)
        putString("errorMessage", errorMessage)
      }

  companion object {
    fun fromBundle(bundle: Bundle?): PlaybackStatusSnapshot {
      if (bundle == null) {
        return PlaybackStatusSnapshot()
      }

      return PlaybackStatusSnapshot(
          hasTrack = bundle.getBoolean("hasTrack"),
          track = PlaybackTrack.fromBundle(bundle.getBundle("track")),
          isPlaying = bundle.getBoolean("isPlaying"),
          isBuffering = bundle.getBoolean("isBuffering"),
          position = bundle.getDouble("position"),
          duration = bundle.getDouble("duration"),
          errorMessage = bundle.getString("errorMessage"),
      )
    }
  }
}

class PlaybackService : Service(), AudioManager.OnAudioFocusChangeListener {
  private val handler = Handler(Looper.getMainLooper())
  private val progressRunnable =
      object : Runnable {
        override fun run() {
          publishStatus()
          if (currentTrack != null && (isPlaying || isBuffering)) {
            handler.postDelayed(this, PROGRESS_UPDATE_INTERVAL_MS)
          }
        }
      }

  private lateinit var notificationManager: NotificationManager
  private lateinit var audioManager: AudioManager
  private lateinit var mediaSession: MediaSessionCompat

  private var audioFocusRequest: AudioFocusRequest? = null
  private var currentTrack: PlaybackTrack? = null
  private var errorMessage: String? = null
  private var isBuffering = false
  private var isForegroundService = false
  private var isPlaying = false
  private var lastKnownDurationMs = 0
  private var mediaPlayer: MediaPlayer? = null
  private var tidalPlaybackSession: TidalPlaybackSession? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onCreate() {
    super.onCreate()
    notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    mediaSession = MediaSessionCompat(this, MEDIA_SESSION_TAG).apply {
      setFlags(
          MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
              MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
      )
      setCallback(
          object : MediaSessionCompat.Callback() {
            override fun onPause() {
              pausePlayback()
            }

            override fun onPlay() {
              playPlayback()
            }

            override fun onSeekTo(pos: Long) {
              seekToPlayback(pos / 1000.0)
            }

            override fun onStop() {
              stopPlayback()
            }
          }
      )
      isActive = false
    }

    createNotificationChannel()
    latestStatusSnapshot = PlaybackStatusSnapshot()
  }

  override fun onDestroy() {
    stopProgressUpdates()
    releasePlayer()
    abandonAudioFocus()
    mediaSession.release()
    isForegroundService = false
    super.onDestroy()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_LOAD -> handleLoad(intent)
      ACTION_PAUSE -> pausePlayback()
      ACTION_PLAY -> playPlayback()
      ACTION_SEEK -> seekToPlayback(intent.getDoubleExtra(EXTRA_POSITION, 0.0))
      ACTION_STOP -> stopPlayback()
      else -> publishStatus()
    }

    return START_NOT_STICKY
  }

  override fun onAudioFocusChange(focusChange: Int) {
    when (focusChange) {
      AudioManager.AUDIOFOCUS_LOSS,
      AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
      AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> pausePlayback()
    }
  }

  private fun handleLoad(intent: Intent) {
    val requestedTrack = PlaybackTrack.fromIntent(intent)
    if (requestedTrack.source == "tidal") {
      if (requestedTrack.id.isNullOrBlank() ||
          requestedTrack.backendUrl.isNullOrBlank() ||
          requestedTrack.sessionToken.isNullOrBlank()) {
        errorMessage = "Tidal playback could not start. Please reconnect Tidal and try again."
        publishStatus()
        return
      }
    } else if (requestedTrack.url.isNullOrBlank()) {
      errorMessage = "This track could not be played."
      publishStatus()
      return
    }

    if (currentTrack?.key == requestedTrack.key &&
        (requestedTrack.source == "tidal" || currentTrack?.url == requestedTrack.url)) {
      currentTrack = requestedTrack
      errorMessage = null
      publishStatus()
      playPlayback()
      return
    }

    stopProgressUpdates()
    releasePlayer()

    currentTrack = requestedTrack
    errorMessage = null
    isBuffering = true
    isPlaying = false
    lastKnownDurationMs = 0
    mediaSession.isActive = true
    updateMetadata()
    updatePlaybackState()
    ensureForeground()
    publishStatus()

    if (requestedTrack.source == "tidal") {
      loadTidalTrack(requestedTrack)
      return
    }

    val player = MediaPlayer()
    mediaPlayer = player
    player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
    player.setAudioAttributes(
        AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .build()
    )
    player.setOnPreparedListener {
      lastKnownDurationMs = it.duration.coerceAtLeast(0)
      isBuffering = false
      errorMessage = null
      updateMetadata()
      playPlayback()
    }
    player.setOnCompletionListener {
      isPlaying = false
      isBuffering = false
      stopProgressUpdates()
      try {
        it.seekTo(0)
      } catch (_: IllegalStateException) {
      }
      updatePlaybackState()
      updateNotification()
      publishStatus()
    }
    player.setOnErrorListener { _, _, _ ->
      errorMessage = "This track could not be played."
      isPlaying = false
      isBuffering = false
      stopProgressUpdates()
      updatePlaybackState()
      updateNotification()
      publishStatus()
      true
    }
    player.setOnInfoListener { _, what, _ ->
      when (what) {
        MediaPlayer.MEDIA_INFO_BUFFERING_START -> {
          isBuffering = true
          updatePlaybackState()
          updateNotification()
          publishStatus()
          true
        }
        MediaPlayer.MEDIA_INFO_BUFFERING_END -> {
          isBuffering = false
          updatePlaybackState()
          updateNotification()
          publishStatus()
          true
        }
        else -> false
      }
    }
    player.setOnSeekCompleteListener {
      updatePlaybackState()
      publishStatus()
    }

    try {
      player.setDataSource(applicationContext, Uri.parse(requestedTrack.url))
      player.prepareAsync()
    } catch (error: Exception) {
      errorMessage = "This track could not be played."
      isBuffering = false
      isPlaying = false
      stopProgressUpdates()
      updatePlaybackState()
      updateNotification()
      publishStatus()
    }
  }

  private fun loadTidalTrack(requestedTrack: PlaybackTrack) {
    val application = application as? android.app.Application
    if (application == null) {
      errorMessage = "Tidal playback could not start."
      isBuffering = false
      updatePlaybackState()
      updateNotification()
      publishStatus()
      return
    }

    try {
      val session =
          TidalPlaybackSession(
              application = application,
              track = requestedTrack,
              onCompletion = {
                isPlaying = false
                isBuffering = false
                errorMessage = null
                stopProgressUpdates()
                updatePlaybackState()
                updateNotification()
                publishStatus()
              },
              onError = { message ->
                errorMessage = message
                isPlaying = false
                isBuffering = false
                stopProgressUpdates()
                updatePlaybackState()
                updateNotification()
                publishStatus()
              },
              onSnapshot = { snapshot ->
                lastKnownDurationMs = (snapshot.durationSeconds * 1000.0).roundToInt().coerceAtLeast(0)
                isPlaying = snapshot.isPlaying
                isBuffering = snapshot.isBuffering
                if (snapshot.errorMessage != null) {
                  errorMessage = snapshot.errorMessage
                }
                if (isPlaying || isBuffering) {
                  startProgressUpdates()
                } else {
                  stopProgressUpdates()
                }
                updateMetadata()
                updatePlaybackState()
                updateNotification()
                publishStatus()
              },
          )
      tidalPlaybackSession = session
      session.load(requestedTrack)
    } catch (_: Exception) {
      errorMessage = "This track could not be played."
      isBuffering = false
      isPlaying = false
      stopProgressUpdates()
      updatePlaybackState()
      updateNotification()
      publishStatus()
    }
  }

  private fun playPlayback() {
    if (!requestAudioFocus()) {
      errorMessage = "Playback could not start."
      publishStatus()
      return
    }

    tidalPlaybackSession?.let { tidalSession ->
      try {
        tidalSession.play()
        errorMessage = null
        isPlaying = true
        isBuffering = false
        ensureForeground()
        startProgressUpdates()
        updatePlaybackState()
        updateNotification()
        publishStatus()
      } catch (_: Exception) {
        errorMessage = "Playback could not start."
        isPlaying = false
        isBuffering = false
        stopProgressUpdates()
        updatePlaybackState()
        updateNotification()
        publishStatus()
      }
      return
    }

    val player = mediaPlayer ?: return

    try {
      if (!player.isPlaying) {
        player.start()
      }
      errorMessage = null
      isPlaying = true
      isBuffering = false
      ensureForeground()
      startProgressUpdates()
      updatePlaybackState()
      updateNotification()
      publishStatus()
    } catch (_: IllegalStateException) {
      errorMessage = "Playback could not start."
      isPlaying = false
      isBuffering = false
      stopProgressUpdates()
      updatePlaybackState()
      updateNotification()
      publishStatus()
    }
  }

  private fun pausePlayback() {
    tidalPlaybackSession?.let { tidalSession ->
      try {
        tidalSession.pause()
      } catch (_: Exception) {
      }

      isPlaying = false
      isBuffering = false
      stopProgressUpdates()
      updatePlaybackState()
      updateNotification()
      publishStatus()
      return
    }

    val player = mediaPlayer ?: return

    try {
      if (player.isPlaying) {
        player.pause()
      }
    } catch (_: IllegalStateException) {
    }

    isPlaying = false
    isBuffering = false
    stopProgressUpdates()
    updatePlaybackState()
    updateNotification()
    publishStatus()
  }

  private fun seekToPlayback(positionSeconds: Double) {
    tidalPlaybackSession?.let { tidalSession ->
      try {
        tidalSession.seek(positionSeconds)
        publishStatus()
      } catch (_: Exception) {
      }
      return
    }

    val player = mediaPlayer ?: return
    val maxDurationMs =
        if (lastKnownDurationMs > 0) {
          lastKnownDurationMs
        } else {
          player.duration.coerceAtLeast(0)
        }
    val nextPositionMs = (positionSeconds * 1000.0).roundToInt().coerceIn(0, maxDurationMs)

    try {
      player.seekTo(nextPositionMs)
      publishStatus()
    } catch (_: IllegalStateException) {
    }
  }

  private fun stopPlayback() {
    stopProgressUpdates()
    releasePlayer()
    abandonAudioFocus()
    currentTrack = null
    errorMessage = null
    isPlaying = false
    isBuffering = false
    lastKnownDurationMs = 0
    mediaSession.isActive = false
    updatePlaybackState()
    notificationManager.cancel(NOTIFICATION_ID)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(true)
    }
    isForegroundService = false
    publishStatus()
    stopSelf()
  }

  private fun releasePlayer() {
    tidalPlaybackSession?.release()
    tidalPlaybackSession = null

    val player = mediaPlayer ?: return
    try {
      player.reset()
    } catch (_: IllegalStateException) {
    }
    player.release()
    mediaPlayer = null
  }

  private fun requestAudioFocus(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val request =
          audioFocusRequest
              ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                  .setAudioAttributes(
                      AudioAttributes.Builder()
                          .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                          .setUsage(AudioAttributes.USAGE_MEDIA)
                          .build()
                  )
                  .setOnAudioFocusChangeListener(this)
                  .build()
                  .also { audioFocusRequest = it }

      audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    } else {
      @Suppress("DEPRECATION")
      audioManager.requestAudioFocus(
          this,
          AudioManager.STREAM_MUSIC,
          AudioManager.AUDIOFOCUS_GAIN,
      ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }
  }

  private fun abandonAudioFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
    } else {
      @Suppress("DEPRECATION")
      audioManager.abandonAudioFocus(this)
    }
  }

  private fun startProgressUpdates() {
    handler.removeCallbacks(progressRunnable)
    handler.post(progressRunnable)
  }

  private fun stopProgressUpdates() {
    handler.removeCallbacks(progressRunnable)
  }

  private fun ensureForeground() {
    val notification = buildNotification() ?: return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(
          NOTIFICATION_ID,
          notification,
          ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
      )
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }
    isForegroundService = true
  }

  private fun updateNotification() {
    val notification = buildNotification() ?: return
    if (isForegroundService) {
      notificationManager.notify(NOTIFICATION_ID, notification)
    }
  }

  private fun buildNotification(): Notification? {
    val track = currentTrack ?: return null
    val openAppIntent =
        packageManager.getLaunchIntentForPackage(packageName)?.apply {
          flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
    val contentIntent =
        PendingIntent.getActivity(
            this,
            REQUEST_OPEN_APP,
            openAppIntent,
            pendingIntentFlags(PendingIntent.FLAG_UPDATE_CURRENT),
        )
    val playPauseIntent =
        Intent(this, PlaybackService::class.java).apply {
          action = if (isPlaying) ACTION_PAUSE else ACTION_PLAY
        }
    val playPausePendingIntent =
        PendingIntent.getService(
            this,
            REQUEST_PLAY_PAUSE,
            playPauseIntent,
            pendingIntentFlags(PendingIntent.FLAG_UPDATE_CURRENT),
        )
    val stopIntent =
        Intent(this, PlaybackService::class.java).apply {
          action = ACTION_STOP
        }
    val stopPendingIntent =
        PendingIntent.getService(
            this,
            REQUEST_STOP,
            stopIntent,
            pendingIntentFlags(PendingIntent.FLAG_UPDATE_CURRENT),
        )

    return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
        .setContentIntent(contentIntent)
        .setContentText(track.artist ?: track.album ?: track.source ?: getString(R.string.app_name))
        .setContentTitle(track.title ?: getString(R.string.app_name))
        .setDeleteIntent(stopPendingIntent)
        .setOngoing(isPlaying || isBuffering)
        .setOnlyAlertOnce(true)
        .setShowWhen(false)
        .setSmallIcon(android.R.drawable.ic_media_play)
        .setStyle(
            androidx.media.app.NotificationCompat.MediaStyle()
                .setMediaSession(mediaSession.sessionToken)
                .setShowActionsInCompactView(0, 1)
        )
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .addAction(
            if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
            if (isPlaying) "Pause" else "Play",
            playPausePendingIntent,
        )
        .addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Stop",
            stopPendingIntent,
        )
        .build()
  }

  private fun updateMetadata() {
    val metadata =
        MediaMetadataCompat.Builder().apply {
          val track = currentTrack
          if (track != null) {
            putString(MediaMetadataCompat.METADATA_KEY_TITLE, track.title)
            putString(MediaMetadataCompat.METADATA_KEY_ARTIST, track.artist)
            putString(MediaMetadataCompat.METADATA_KEY_ALBUM, track.album)
            putLong(MediaMetadataCompat.METADATA_KEY_DURATION, lastKnownDurationMs.toLong())
          }
        }.build()

    mediaSession.setMetadata(metadata)
  }

  private fun updatePlaybackState() {
    val positionMs = currentPositionMs().toLong()
    val state =
        when {
          errorMessage != null -> PlaybackStateCompat.STATE_ERROR
          isBuffering -> PlaybackStateCompat.STATE_BUFFERING
          isPlaying -> PlaybackStateCompat.STATE_PLAYING
          currentTrack != null -> PlaybackStateCompat.STATE_PAUSED
          else -> PlaybackStateCompat.STATE_STOPPED
        }

    val playbackState =
        PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_SEEK_TO or
                    PlaybackStateCompat.ACTION_STOP
            )
            .setState(state, positionMs, if (isPlaying) 1f else 0f)

    if (errorMessage != null) {
      playbackState.setErrorMessage(errorMessage)
    }

    mediaSession.setPlaybackState(playbackState.build())
  }

  private fun publishStatus() {
    val snapshot =
        PlaybackStatusSnapshot(
            hasTrack = currentTrack != null,
            track = currentTrack,
            isPlaying = isPlaying,
            isBuffering = isBuffering,
            position = currentPositionMs() / 1000.0,
            duration = currentDurationSeconds(),
            errorMessage = errorMessage,
        )
    latestStatusSnapshot = snapshot
    sendBroadcast(
        Intent(ACTION_STATUS_CHANGED).apply {
          `package` = packageName
          putExtras(snapshot.toBundle())
        }
    )
  }

  private fun currentDurationSeconds(): Double {
    val tidalDurationMs = tidalPlaybackSession?.snapshot()?.let { (it.durationSeconds * 1000.0).roundToInt() }
    val durationMs =
        when {
          tidalDurationMs != null -> tidalDurationMs
          lastKnownDurationMs > 0 -> lastKnownDurationMs
          else ->
              mediaPlayer?.let {
                try {
                  it.duration
                } catch (_: IllegalStateException) {
                  0
                }
              } ?: 0
        }

    return durationMs.coerceAtLeast(0) / 1000.0
  }

  private fun currentPositionMs(): Int {
    tidalPlaybackSession?.let { tidalSession ->
      return (tidalSession.snapshot().positionSeconds * 1000.0).roundToInt().coerceAtLeast(0)
    }

    val player = mediaPlayer ?: return 0
    return try {
      player.currentPosition.coerceAtLeast(0)
    } catch (_: IllegalStateException) {
      0
    }
  }

  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }

    val channel =
        NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Playback",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
          description = "Playback controls for the current track"
          lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

    notificationManager.createNotificationChannel(channel)
  }

  private fun pendingIntentFlags(baseFlags: Int): Int {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      baseFlags or PendingIntent.FLAG_IMMUTABLE
    } else {
      baseFlags
    }
  }

  companion object {
    const val ACTION_LOAD = "com.musestructnative.playback.LOAD"
    const val ACTION_PAUSE = "com.musestructnative.playback.PAUSE"
    const val ACTION_PLAY = "com.musestructnative.playback.PLAY"
    const val ACTION_SEEK = "com.musestructnative.playback.SEEK"
    const val ACTION_STATUS_CHANGED = "com.musestructnative.playback.STATUS"
    const val ACTION_STOP = "com.musestructnative.playback.STOP"

    const val EXTRA_POSITION = "position"
    const val EXTRA_TRACK_BACKEND_URL = "trackBackendUrl"
    const val EXTRA_TRACK_ALBUM = "trackAlbum"
    const val EXTRA_TRACK_ARTIST = "trackArtist"
    const val EXTRA_TRACK_ARTWORK_URL = "trackArtworkUrl"
    const val EXTRA_TRACK_DESCRIPTION = "trackDescription"
    const val EXTRA_TRACK_ID = "trackId"
    const val EXTRA_TRACK_KEY = "trackKey"
    const val EXTRA_TRACK_SESSION_TOKEN = "trackSessionToken"
    const val EXTRA_TRACK_SOURCE = "trackSource"
    const val EXTRA_TRACK_TITLE = "trackTitle"
    const val EXTRA_TRACK_URL = "trackUrl"

    private const val MEDIA_SESSION_TAG = "MusestructPlayback"
    private const val NOTIFICATION_CHANNEL_ID = "musestruct.playback"
    private const val NOTIFICATION_ID = 4102
    private const val PROGRESS_UPDATE_INTERVAL_MS = 500L
    private const val REQUEST_OPEN_APP = 4103
    private const val REQUEST_PLAY_PAUSE = 4104
    private const val REQUEST_STOP = 4105

    @Volatile private var latestStatusSnapshot = PlaybackStatusSnapshot()

    internal fun latestStatus(): PlaybackStatusSnapshot = latestStatusSnapshot
  }
}