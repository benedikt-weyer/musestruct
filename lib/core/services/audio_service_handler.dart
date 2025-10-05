import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import '../../music/models/music.dart';

/// Audio service handler that integrates with the audio_service package
/// to provide media controls on all platforms:
/// - Android: Media notifications, lock screen, headset buttons, Android Auto
/// - iOS: Lock screen, control center, headset buttons
/// - Web: Media session API
/// - Linux: MPRIS (Media Player Remote Interfacing Specification)
class MusestructAudioHandler extends BaseAudioHandler with SeekHandler {
  // Callback functions to control the actual audio player
  // These are mutable so they can be set after initialization
  Future<void> Function()? onPlayCallback;
  Future<void> Function()? onPauseCallback;
  Future<void> Function()? onStopCallback;
  Future<void> Function(Duration position)? onSeekCallback;
  Future<void> Function()? onSkipToNextCallback;
  Future<void> Function()? onSkipToPreviousCallback;

  MusestructAudioHandler({
    this.onPlayCallback,
    this.onPauseCallback,
    this.onStopCallback,
    this.onSeekCallback,
    this.onSkipToNextCallback,
    this.onSkipToPreviousCallback,
  });

  @override
  Future<void> play() async {
    debugPrint('AudioServiceHandler: Play requested');
    if (onPlayCallback != null) {
      await onPlayCallback!();
    }
  }

  @override
  Future<void> pause() async {
    debugPrint('AudioServiceHandler: Pause requested');
    if (onPauseCallback != null) {
      await onPauseCallback!();
    }
  }

  @override
  Future<void> stop() async {
    debugPrint('AudioServiceHandler: Stop requested');
    if (onStopCallback != null) {
      await onStopCallback!();
    }
    // Clear the media item when stopped
    mediaItem.add(null);
    playbackState.add(PlaybackState(
      controls: [],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('AudioServiceHandler: Seek to ${position.inSeconds}s requested');
    if (onSeekCallback != null) {
      await onSeekCallback!(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('AudioServiceHandler: Skip to next requested');
    if (onSkipToNextCallback != null) {
      await onSkipToNextCallback!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('AudioServiceHandler: Skip to previous requested');
    if (onSkipToPreviousCallback != null) {
      await onSkipToPreviousCallback!();
    }
  }

  /// Update the media item with track information
  void updateTrackInfo(Track track) {
    debugPrint('AudioServiceHandler: Updating media item for ${track.title} by ${track.artist}');
    
    final item = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration != null ? Duration(seconds: track.duration!) : null,
      artUri: track.coverUrl != null ? Uri.parse(track.coverUrl!) : null,
      extras: {
        'source': track.source,
        if (track.quality != null) 'quality': track.quality,
        if (track.bitrate != null) 'bitrate': track.bitrate,
        if (track.sampleRate != null) 'sampleRate': track.sampleRate,
        if (track.bitDepth != null) 'bitDepth': track.bitDepth,
        if (track.bpm != null) 'bpm': track.bpm,
        if (track.keyName != null) 'keyName': track.keyName,
        if (track.camelot != null) 'camelot': track.camelot,
      },
    );
    
    mediaItem.add(item);
    debugPrint('AudioServiceHandler: Media item updated - Title: ${item.title}, Artist: ${item.artist}, Album: ${item.album}');
  }

  /// Update the playback state
  void updatePlaybackState({
    required bool playing,
    required Duration position,
    required Duration duration,
    AudioProcessingState processingState = AudioProcessingState.ready,
    bool hasNext = false,
    bool hasPrevious = false,
  }) {
    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      if (playing)
        MediaControl.pause
      else
        MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
      MediaControl.stop,
    ];

    final state = PlaybackState(
      controls: controls,
      systemActions: {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.seek,
        if (hasNext) MediaAction.skipToNext,
        if (hasPrevious) MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: hasPrevious 
          ? [0, 1, 2] // Previous, Play/Pause, Next
          : [0, 1], // Play/Pause, Next (or just Play/Pause if no next)
      processingState: processingState,
      playing: playing,
      updatePosition: position,
      bufferedPosition: duration,
      speed: playing ? 1.0 : 0.0,
      queueIndex: 0,
    );
    
    playbackState.add(state);
    debugPrint('AudioServiceHandler: Playback state updated - Playing: $playing, Position: ${position.inSeconds}s/${duration.inSeconds}s, HasNext: $hasNext, HasPrevious: $hasPrevious');
  }

  /// Clear the current media item and reset state
  void clearMediaItem() {
    debugPrint('AudioServiceHandler: Clearing media item');
    mediaItem.add(null);
    playbackState.add(PlaybackState(
      controls: [],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }
}

