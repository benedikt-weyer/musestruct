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
  Future<void> Function()? onToggleFavoriteCallback;

  MusestructAudioHandler({
    this.onPlayCallback,
    this.onPauseCallback,
    this.onStopCallback,
    this.onSeekCallback,
    this.onSkipToNextCallback,
    this.onSkipToPreviousCallback,
    this.onToggleFavoriteCallback,
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

  @override
  Future<void> setRating(Rating rating, [Map<String, dynamic>? extras]) async {
    debugPrint('AudioServiceHandler: Toggle favorite requested');
    // Using setRating as toggle favorite action
    if (onToggleFavoriteCallback != null) {
      await onToggleFavoriteCallback!();
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
    bool isFavorite = false,
  }) {
    // Build controls list with all available actions
    // Always show all 4 buttons for a consistent UI
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (playing)
        MediaControl.pause
      else
        MediaControl.play,
      MediaControl.skipToNext,
      MediaControl(
        androidIcon: isFavorite ? 'drawable/ic_stat_favorite' : 'drawable/ic_stat_favorite_border',
        label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
        action: MediaAction.setRating, // Using setRating as a proxy for favorite/like
      ),
    ];
    
    debugPrint('AudioServiceHandler: Controls list has ${controls.length} items, isFavorite: $isFavorite');

    // Determine which controls to show in compact view (up to 3 on Android)
    // Show: Previous, Play/Pause, Next in compact view
    // Favorite button only shows in expanded view
    final compactIndices = [0, 1, 2]; // Previous, Play/Pause, Next

    final state = PlaybackState(
      controls: controls,
      systemActions: {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.seek,
        MediaAction.setRating, // For favorite/like functionality
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: compactIndices,
      processingState: processingState,
      playing: playing,
      updatePosition: position,
      bufferedPosition: position, // Use current position for buffered position
      speed: playing ? 1.0 : 0.0,
      queueIndex: 0,
    );
    
    playbackState.add(state);
    
    // Also update media item with duration to ensure seek bar shows
    if (mediaItem.value != null && duration.inSeconds > 0) {
      final currentItem = mediaItem.value!;
      if (currentItem.duration != duration) {
        mediaItem.add(currentItem.copyWith(duration: duration));
      }
    }
    
    debugPrint('AudioServiceHandler: Playback state updated - Playing: $playing, Position: ${position.inSeconds}s/${duration.inSeconds}s, HasNext: $hasNext, HasPrevious: $hasPrevious, IsFavorite: $isFavorite, Controls: ${controls.length}');
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

