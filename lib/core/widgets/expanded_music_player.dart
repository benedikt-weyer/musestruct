import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/providers/music_provider.dart';
import '../../music/providers/saved_tracks_provider.dart';
import '../../queue/providers/queue_provider.dart';
import '../../playlists/providers/playlist_provider.dart';
import '../screens/queue/queue_screen.dart';
import '../screens/playlists/select_playlist_dialog.dart';
import '../services/audio_analysis_service.dart';
import '../services/api_service.dart';
import '../../music/models/music.dart';

class ExpandedMusicPlayer extends StatelessWidget {
  final MusicProvider musicProvider;

  const ExpandedMusicPlayer({super.key, required this.musicProvider});

  Color _getSourceColor(String source, BuildContext context) {
    switch (source.toLowerCase()) {
      case 'qobuz':
        return const Color(0xFF00D4AA);
      case 'spotify':
        return const Color(0xFF1DB954);
      case 'tidal':
        return const Color(0xFF000000);
      case 'apple_music':
        return const Color(0xFFFA243C);
      case 'youtube_music':
        return const Color(0xFFFF0000);
      case 'deezer':
        return const Color(0xFF00C7B7);
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

        return SizedBox(
          // Force full width
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height -
              MediaQuery.of(context).padding.top -
              MediaQuery.of(context).padding.bottom -
              kBottomNavigationBarHeight -
              40,
          child: Container(
            // Use full width and flexible height
            width: double.infinity,
            constraints: const BoxConstraints(
              maxWidth: double.infinity,
            ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            top: false, // Don't apply top safe area since this is a bottom sheet
            child: Column(
              children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with close button
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width > 600 ? 20 : 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Now Playing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                    ),
                  ],
                ),
              ),

              // Content with responsive cover art
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                    const SizedBox(height: 10),

                    // Responsive album art
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate appropriate size based on available space and screen width
                        final screenWidth = MediaQuery.of(context).size.width;
                        final availableHeight = constraints.maxHeight;
                        final availableWidth = constraints.maxWidth;
                        
                        // Calculate maximum cover size to prevent overflow
                        // Reserve space for song info (~100px), progress bar (~60px), controls (~80px), and padding (~60px)
                        final reservedSpace = 300.0;
                        final maxHeightForCover = (availableHeight - reservedSpace).clamp(120.0, double.infinity);
                        
                        double maxCoverSize;
                        if (screenWidth > 600) {
                          // For large screens, use up to 50% of width but constrain by available height
                          final widthBasedSize = (availableWidth * 0.5).clamp(200.0, 400.0);
                          final heightBasedSize = maxHeightForCover.clamp(150.0, 400.0);
                          maxCoverSize = widthBasedSize < heightBasedSize ? widthBasedSize : heightBasedSize;
                        } else {
                          // For small screens, prioritize height constraint to prevent overflow
                          final widthBasedSize = (availableWidth * 0.7).clamp(150.0, 300.0);
                          final heightBasedSize = maxHeightForCover.clamp(120.0, 280.0);
                          maxCoverSize = widthBasedSize < heightBasedSize ? widthBasedSize : heightBasedSize;
                        }

                        return Container(
                          width: maxCoverSize,
                          height: maxCoverSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.grey[300],
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: track.coverUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(
                                    track.coverUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.music_note,
                                        size: 120,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      );
                                    },
                                  ),
                                )
                              : Icon(
                                  Icons.music_note,
                                  size: 120,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Song info
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 20,
                      ),
                      child: Column(
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            track.artist,
                            style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          
                          // BPM display - show when available
                          if (track.bpm != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.speed,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${track.bpm!.toStringAsFixed(0)} BPM',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Consumer<QueueProvider>(
                            builder: (context, queueProvider, child) {
                              // Try to get playlist name from the first playlist queue item
                              final playlistName =
                                  queueProvider.playlistQueue.isNotEmpty
                                  ? queueProvider
                                        .playlistQueue
                                        .first
                                        .playlistName
                                  : null;
                              final albumOrPlaylist =
                                  playlistName ?? track.album;
                              if (albumOrPlaylist.isNotEmpty) {
                                return Text(
                                  albumOrPlaylist,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          const SizedBox(height: 12),
                          // Source and quality info
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getSourceColor(
                                    track.source,
                                    context,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _getSourceColor(
                                      track.source,
                                      context,
                                    ).withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  track.formattedSource,
                                  style: TextStyle(
                                    color: _getSourceColor(track.source, context),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (track.formattedQuality.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  track.formattedQuality,
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 15),

                    // Progress bar and time
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 20,
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTapDown: (details) async {
                              if (musicProvider.duration.inMilliseconds > 0) {
                                final RenderBox progressBarBox =
                                    context.findRenderObject() as RenderBox;
                                final progressBarWidth =
                                    progressBarBox.size.width;
                                final tapPosition = details.localPosition.dx;
                                final progress =
                                    (tapPosition / progressBarWidth).clamp(
                                      0.0,
                                      1.0,
                                    );
                                final newPosition = Duration(
                                  milliseconds:
                                      (musicProvider.duration.inMilliseconds *
                                              progress)
                                          .round(),
                                );

                                try {
                                  await musicProvider.seekTo(newPosition);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Seek not supported for this audio format',
                                        ),
                                        duration: Duration(seconds: 2),
                                        backgroundColor: Colors.orange,
                                        behavior: SnackBarBehavior.floating,
                                        margin: EdgeInsets.only(bottom: 100, left: 16, right: 16),
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: Stack(
                                  children: [
                                    // Progress bar
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: musicProvider.duration.inMilliseconds > 0
                                            ? (musicProvider.position.inMilliseconds /
                                              musicProvider.duration.inMilliseconds).clamp(0.0, 1.0)
                                            : 0.0,
                                        child: Container(
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).brightness == Brightness.dark 
                                                ? Colors.white 
                                                : Theme.of(context).primaryColor,
                                            borderRadius: const BorderRadius.only(
                                              topRight: Radius.circular(2),
                                              bottomRight: Radius.circular(2),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(musicProvider.position),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _formatDuration(musicProvider.duration),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Main controls
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width > 600 ? 40 : 20,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Stop button
                          IconButton(
                            onPressed: musicProvider.stopPlayback,
                            icon: const Icon(Icons.stop, size: 32),
                            iconSize: 32,
                          ),

                          // Play/Pause button
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: musicProvider.isLoading
                                  ? null
                                  : musicProvider.togglePlayPause,
                              icon: musicProvider.isLoading
                                  ? const SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      musicProvider.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 36,
                                      color: Colors.white,
                                    ),
                            ),
                          ),

                          // Next button
                          Consumer<QueueProvider>(
                            builder: (context, queueProvider, child) {
                              final hasNextTrack = queueProvider.hasNextTrack();
                              return IconButton(
                                onPressed:
                                    hasNextTrack && !musicProvider.isLoading
                                    ? musicProvider.playNextTrack
                                    : null,
                                icon: const Icon(Icons.skip_next, size: 32),
                                iconSize: 32,
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(30, 0, 30, 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Queue button
                          Consumer<QueueProvider>(
                            builder: (context, queueProvider, child) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          Navigator.of(
                                            context,
                                          ).pop(); // Close expanded player
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const QueueScreen(),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.queue_music,
                                          size: 28,
                                        ),
                                      ),
                                      if (queueProvider.queueLength > 0)
                                        Positioned(
                                          right: 6,
                                          top: 6,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).primaryColor,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 16,
                                              minHeight: 16,
                                            ),
                                            child: Text(
                                              '${queueProvider.queueLength}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    'Queue',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                          // Save button
                          Consumer<SavedTracksProvider>(
                            builder: (context, savedTracksProvider, child) {
                              final isSaved = savedTracksProvider.isTrackSaved(
                                track.id,
                                track.source,
                              );
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
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
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                      size: 28,
                                    ),
                                  ),
                                  Text(
                                    isSaved ? 'Saved' : 'Save',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                          // Playlist button
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) =>
                                        SelectPlaylistDialog(track: track),
                                  );
                                },
                                icon: const Icon(Icons.playlist_add, size: 28),
                              ),
                              Text(
                                'Playlist',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),

                          // Analyse button
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _analyzeBpm(context, track),
                                icon: const Icon(Icons.analytics, size: 28),
                              ),
                              Text(
                                track.bpm != null ? '${track.bpm!.toStringAsFixed(0)} BPM' : 'Analyze',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),

                          // Remove from playlist button (only show when playing from playlist)
                          if (musicProvider.isPlayingFromPlaylist && musicProvider.currentPlaylistQueueItem != null)
                            Consumer<PlaylistProvider>(
                              builder: (context, playlistProvider, child) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () => _removeFromPlaylist(context, musicProvider, playlistProvider),
                                      icon: const Icon(Icons.playlist_remove, size: 28),
                                    ),
                                    Text(
                                      'Remove',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
                ),
              ),
            ],
            ),
          ),
          ),
        );
      },
    );
  }

  Future<void> _handleSaveAction(
    BuildContext context,
    MusicProvider musicProvider,
    SavedTracksProvider savedTracksProvider,
    bool isSaved,
  ) async {
    if (isSaved) {
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
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
          ),
        );

        // Skip to next track since the current one was removed
        await musicProvider.playNextTrack();
        // Close the expanded player since we're moving to next track
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove "${currentTrack.title}" from playlist'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
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
