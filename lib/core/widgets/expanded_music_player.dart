import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/providers/music_provider.dart';
import '../../music/providers/saved_tracks_provider.dart';
import '../../queue/providers/queue_provider.dart';
import '../screens/queue/queue_screen.dart';
import '../screens/playlists/select_playlist_dialog.dart';

class ExpandedMusicPlayer extends StatelessWidget {
  final MusicProvider musicProvider;

  const ExpandedMusicPlayer({super.key, required this.musicProvider});

  Color _getSourceColor(String source) {
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
        return Colors.grey[600]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final track = musicProvider.currentTrack;
        if (track == null) return const SizedBox.shrink();

        return Container(
          // Use flexible height that respects the constraints from the modal sheet
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                MediaQuery.of(context).padding.bottom -
                kBottomNavigationBarHeight -
                40, // Reduced from 80 to 40 to make it taller
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
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with close button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    const SizedBox(height: 20),

                    // Responsive album art
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate appropriate size based on available space
                        final availableHeight = constraints.maxHeight;
                        final maxCoverSize = (availableHeight * 0.4).clamp(
                          150.0,
                          280.0,
                        );

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
                                        color: Colors.grey[600],
                                      );
                                    },
                                  ),
                                )
                              : Icon(
                                  Icons.music_note,
                                  size: 120,
                                  color: Colors.grey[600],
                                ),
                        );
                      },
                    ),

                    // Song info
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
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
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                                    color: Colors.grey[500],
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
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _getSourceColor(
                                      track.source,
                                    ).withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  track.formattedSource,
                                  style: TextStyle(
                                    color: _getSourceColor(track.source),
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

                    // Progress bar and time
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
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
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: musicProvider.duration.inMilliseconds > 0
                                    ? (musicProvider.position.inMilliseconds /
                                              musicProvider
                                                  .duration
                                                  .inMilliseconds)
                                          .clamp(0.0, 1.0)
                                    : 0,
                                onChanged: null, // Handled by gesture detector
                                activeColor: Theme.of(context).primaryColor,
                                inactiveColor: Colors.grey[300],
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(musicProvider.position),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _formatDuration(musicProvider.duration),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Main controls
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
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
                              final hasNextTrack =
                                  queueProvider.getNextTrack() != null;
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
                                      color: Colors.grey[600],
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
                                          : Colors.grey[600],
                                      size: 28,
                                    ),
                                  ),
                                  Text(
                                    isSaved ? 'Saved' : 'Save',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
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
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
