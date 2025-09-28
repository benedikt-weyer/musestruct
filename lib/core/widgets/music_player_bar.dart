import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/providers/music_provider.dart';
import '../../music/providers/saved_tracks_provider.dart';
import '../../queue/providers/queue_provider.dart';
import '../../playlists/providers/playlist_provider.dart';
import '../screens/queue/queue_screen.dart';
import '../screens/playlists/select_playlist_dialog.dart';
import 'expanded_music_player.dart';
import '../services/audio_analysis_service.dart';
import '../services/api_service.dart';
import '../../music/models/music.dart';

class MusicPlayerBar extends StatelessWidget {
  const MusicPlayerBar({super.key});

  Color _getSourceColor(String source, BuildContext context) {
    switch (source.toLowerCase()) {
      case 'qobuz':
        return const Color(0xFF00D4AA); // Qobuz green
      case 'spotify':
        return const Color(0xFF1DB954); // Spotify green
      case 'tidal':
        return const Color(0xFF000000); // Tidal black
      case 'apple_music':
        return const Color(0xFFFA243C); // Apple Music red
      case 'youtube_music':
        return const Color(0xFFFF0000); // YouTube red
      case 'deezer':
        return const Color(0xFF00C7B7); // Deezer cyan
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final track = musicProvider.currentTrack;
        if (track == null) return const SizedBox.shrink();

        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Progress bar (clickable for seek only)
              GestureDetector(
                onTapDown: (details) async {
                  if (musicProvider.duration.inMilliseconds > 0) {
                    final RenderBox progressBarBox =
                        context.findRenderObject() as RenderBox;
                    final progressBarWidth = progressBarBox.size.width;
                    final tapPosition = details.localPosition.dx;
                    final progress = (tapPosition / progressBarWidth).clamp(
                      0.0,
                      1.0,
                    );
                    final newPosition = Duration(
                      milliseconds:
                          (musicProvider.duration.inMilliseconds * progress)
                              .round(),
                    );

                    try {
                      await musicProvider.seekTo(newPosition);
                    } catch (e) {
                      // Show a brief snackbar if seek fails
                      if (context.mounted) {
                        String message =
                            'Seek not supported for this audio format';
                        if (e.toString().contains('UnsupportedError')) {
                          message =
                              'Seeking not available for ${musicProvider.currentTrack?.source} tracks on Linux';
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            duration: const Duration(seconds: 3),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(
                              bottom: 100,
                              left: 16,
                              right: 16,
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                child: MouseRegion(
                  cursor: musicProvider.audioService.isSeekSupported
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.forbidden,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(3),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(3),
                        bottomRight: Radius.circular(3),
                      ),
                      child: Stack(
                        children: [
                          // Progress bar
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor:
                                  musicProvider.duration.inMilliseconds > 0
                                  ? (musicProvider.position.inMilliseconds /
                                            musicProvider
                                                .duration
                                                .inMilliseconds)
                                        .clamp(0.0, 1.0)
                                  : 0.0,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Theme.of(context).primaryColor,
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(3),
                                    bottomRight: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Player controls
              Expanded(
                child: GestureDetector(
                  onTap: () => _handleTrackInfoTap(context, musicProvider),
                  behavior: HitTestBehavior.translucent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        // Track info area - tappable on small screens
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                _handleTrackInfoTap(context, musicProvider),
                            child: Row(
                              children: [
                                // Album art
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color: Colors.grey[300],
                                  ),
                                  child: track.coverUrl != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Image.network(
                                            track.coverUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Icon(
                                                    Icons.music_note,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  );
                                                },
                                          ),
                                        )
                                      : Icon(
                                          Icons.music_note,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                ),
                                const SizedBox(width: 12),

                                // Track info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        track.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        track.artist,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      // Source and quality info
                                      Row(
                                        children: [
                                          // Source badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getSourceColor(
                                                track.source,
                                                context,
                                              ).withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: _getSourceColor(
                                                  track.source,
                                                  context,
                                                ).withOpacity(0.3),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Text(
                                              track.formattedSource,
                                              style: TextStyle(
                                                color: _getSourceColor(
                                                  track.source,
                                                  context,
                                                ),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          // Audio quality info
                                          if (track.formattedQuality.isNotEmpty)
                                            Text(
                                              track.formattedQuality,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).primaryColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Controls - Use Flexible to prevent overflow
                        Flexible(
                          child: GestureDetector(
                            onTap:
                                () {}, // Empty onTap to prevent propagation to parent
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Position info - hide on small screens
                                if (MediaQuery.of(context).size.width > 600)
                                  Text(
                                    '${_formatDuration(musicProvider.position)} / ${_formatDuration(musicProvider.duration)}',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (MediaQuery.of(context).size.width > 600)
                                  const SizedBox(width: 8),
                                
                                // BPM display - show when available
                                if (musicProvider.currentTrack?.bpm != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${musicProvider.currentTrack!.bpm!.toStringAsFixed(0)} BPM',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                if (musicProvider.currentTrack?.bpm != null)
                                  const SizedBox(width: 8),

                                // Play/Pause button
                                IconButton(
                                  onPressed: musicProvider.isLoading
                                      ? null
                                      : musicProvider.togglePlayPause,
                                  icon: musicProvider.isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          musicProvider.isPlaying
                                              ? Icons.pause
                                              : Icons.play_arrow,
                                          size: 28,
                                        ),
                                ),

                                // Play next track button
                                Consumer<QueueProvider>(
                                  builder: (context, queueProvider, child) {
                                    final hasNextTrack = queueProvider.hasNextTrack();
                                    return IconButton(
                                      onPressed:
                                          hasNextTrack &&
                                              !musicProvider.isLoading
                                          ? musicProvider.playNextTrack
                                          : null,
                                      icon: const Icon(
                                        Icons.skip_next,
                                        size: 20,
                                      ),
                                      tooltip: hasNextTrack
                                          ? 'Play next track'
                                          : 'No next track',
                                    );
                                  },
                                ),

                                // Save/Remove button (heart)
                                Consumer<SavedTracksProvider>(
                                  builder:
                                      (context, savedTracksProvider, child) {
                                        final isSaved = savedTracksProvider
                                            .isTrackSaved(
                                              musicProvider.currentTrack!.id,
                                              musicProvider
                                                  .currentTrack!
                                                  .source,
                                            );
                                        return IconButton(
                                          onPressed: () => _handleSaveAction(
                                            context,
                                            musicProvider,
                                            savedTracksProvider,
                                            isSaved,
                                          ),
                                          icon: Icon(
                                            isSaved
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            color: isSaved
                                                ? Colors.red
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                            size: 20,
                                          ),
                                          tooltip: isSaved
                                              ? 'Remove from saved tracks'
                                              : 'Add to saved tracks',
                                        );
                                      },
                                ),

                                // More actions - show individual buttons on large screens
                                ..._buildActionButtons(context, musicProvider),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildActionButtons(
    BuildContext context,
    MusicProvider musicProvider,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth >= 600;

    if (!isLargeScreen) {
      // On small screens, show an expand button
      return [
        IconButton(
          onPressed: () => _handleTrackInfoTap(context, musicProvider),
          icon: const Icon(Icons.expand_less, size: 20),
          tooltip: 'Expand player',
        ),
      ];
    }

    // On large screens, show individual action buttons
    return [
      // Stop button
      IconButton(
        onPressed: () => musicProvider.stopPlayback(),
        icon: const Icon(Icons.stop, size: 20),
        tooltip: 'Stop playback',
      ),
      
      // Queue button
      Consumer<QueueProvider>(
        builder: (context, queueProvider, child) {
          return IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const QueueScreen()),
            ),
            icon: Stack(
              children: [
                const Icon(Icons.queue_music, size: 20),
                if (queueProvider.queueLength > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '${queueProvider.queueLength}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: queueProvider.queueLength > 0 
              ? 'View Queue (${queueProvider.queueLength})'
              : 'View Queue',
          );
        },
      ),
      
      // Add to playlist button
      IconButton(
        onPressed: () => showDialog(
          context: context,
          builder: (context) => SelectPlaylistDialog(track: musicProvider.currentTrack!),
        ),
        icon: const Icon(Icons.playlist_add, size: 20),
        tooltip: 'Add to playlist',
      ),

      // Analyze BPM button
      IconButton(
        onPressed: () => _analyzeBpm(context, musicProvider.currentTrack!),
        icon: const Icon(Icons.analytics, size: 20),
        tooltip: musicProvider.currentTrack!.bpm != null 
          ? '${musicProvider.currentTrack!.bpm!.toStringAsFixed(0)} BPM'
          : 'Analyze BPM',
      ),

      // Remove from playlist button (only show when playing from playlist)
      if (musicProvider.isPlayingFromPlaylist && musicProvider.currentPlaylistQueueItem != null)
        Consumer<PlaylistProvider>(
          builder: (context, playlistProvider, child) {
            return IconButton(
              onPressed: () => _removeFromPlaylist(context, musicProvider, playlistProvider),
              icon: const Icon(Icons.playlist_remove, size: 20),
              tooltip: 'Remove from playlist',
            );
          },
        ),
      
      // Expand button
      IconButton(
        onPressed: () => _handleTrackInfoTap(context, musicProvider),
        icon: const Icon(Icons.expand_less, size: 20),
        tooltip: 'Expand player',
      ),
    ];
  }

  Future<void> _removeFromPlaylist(
    BuildContext context,
    MusicProvider musicProvider,
    PlaylistProvider playlistProvider,
  ) async {
    final currentTrack = musicProvider.currentTrack;
    final playlistQueueItem = musicProvider.currentPlaylistQueueItem;
    
    if (currentTrack == null || playlistQueueItem == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Playlist'),
        content: Text(
          'Remove "${currentTrack.title}" from "${playlistQueueItem.playlistName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      // Remove the track from the playlist using track information
      final success = await playlistProvider.removeTrackFromPlaylist(
        playlistId: playlistQueueItem.playlistId,
        trackId: currentTrack.id,
        trackSource: currentTrack.source,
        trackTitle: currentTrack.title,
      );

      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${currentTrack.title}" from "${playlistQueueItem.playlistName}"'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Skip to next track since the current one was removed
        await musicProvider.playNextTrack();
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove "${currentTrack.title}" from playlist'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing track: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handleTrackInfoTap(BuildContext context, MusicProvider musicProvider) {
    // Allow expansion on all screen sizes with full width
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      enableDrag: true,
      showDragHandle: false,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width,
        minWidth: MediaQuery.of(context).size.width,
      ),
      builder: (context) => ExpandedMusicPlayer(musicProvider: musicProvider),
    );
  }


  Future<void> _handleSaveAction(
    BuildContext context,
    MusicProvider musicProvider,
    SavedTracksProvider savedTracksProvider,
    bool isSaved,
  ) async {
    if (isSaved) {
      // Find the saved track to remove
      final savedTrack = savedTracksProvider.savedTracks
          .where(
            (st) =>
                st.trackId == musicProvider.currentTrack!.id &&
                st.source == musicProvider.currentTrack!.source,
          )
          .firstOrNull;
      if (savedTrack != null) {
        await savedTracksProvider.removeSavedTrack(
          savedTrack.id,
          musicProvider.currentTrack!.id,
          musicProvider.currentTrack!.source,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed "${musicProvider.currentTrack!.title}" from saved tracks',
              ),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
      }
    } else {
      final success = await savedTracksProvider.saveTrack(
        musicProvider.currentTrack!,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Added "${musicProvider.currentTrack!.title}" to saved tracks'
                  : 'Failed to save track',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _analyzeBpm(BuildContext context, Track track) async {
    try {
      // Get API service from context
      final apiService = Provider.of<ApiService>(context, listen: false);
      final analysisService = AudioAnalysisService(apiService);
      
      // Trigger spectrogram BPM analysis asynchronously (fire and forget)
      analysisService.analyzeBpmSpectrogram(track).then((result) {
        // Update the track with the new BPM value
        if (context.mounted) {
          final musicProvider = Provider.of<MusicProvider>(context, listen: false);
          musicProvider.updateTrackBpm(track.id, result.bpm);
          
          // Also update saved tracks if this track is saved
          final savedTracksProvider = Provider.of<SavedTracksProvider>(context, listen: false);
          savedTracksProvider.updateTrackBpm(track.id, track.source, result.bpm);
          
          // Show success message when analysis completes
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Spectrogram BPM analysis complete: ${result.bpm.toStringAsFixed(1)} BPM\nSpectrogram: ${result.spectrogramPath.split('/').last}\nVisualization: ${result.analysisVisualizationPath.split('/').last}',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }).catchError((e) {
        // Show error message if analysis fails
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Spectrogram BPM analysis failed: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
      
      // Show immediate feedback that analysis has started
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Spectrogram BPM analysis started for "${track.title}"'),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      // Show error message for immediate failures
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start BPM analysis: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
