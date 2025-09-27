import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/providers/music_provider.dart';
import '../../music/providers/saved_tracks_provider.dart';
import '../../queue/providers/queue_provider.dart';
import '../screens/queue/queue_screen.dart';
import '../screens/playlists/select_playlist_dialog.dart';
import 'expanded_music_player.dart';

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

                                // More actions menu
                                _buildMoreActionsMenu(context, musicProvider),
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

  Widget _buildMoreActionsMenu(
    BuildContext context,
    MusicProvider musicProvider,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth >= 600;

    // Only show menu on large screens, small screens use the expandable player
    if (!isLargeScreen) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) => _handleMenuAction(context, value, musicProvider),
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'stop',
          child: Row(
            children: [
              Icon(Icons.stop, size: 20),
              SizedBox(width: 8),
              Text('Stop'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'queue',
          child: Consumer<QueueProvider>(
            builder: (context, queueProvider, child) {
              return Row(
                children: [
                  Stack(
                    children: [
                      const Icon(Icons.queue_music, size: 20),
                      if (queueProvider.queueLength > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
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
                  const SizedBox(width: 8),
                  Text(
                    'View Queue${queueProvider.queueLength > 0 ? ' (${queueProvider.queueLength})' : ''}',
                  ),
                ],
              );
            },
          ),
        ),
        const PopupMenuItem<String>(
          value: 'playlist',
          child: Row(
            children: [
              Icon(Icons.playlist_add, size: 20),
              SizedBox(width: 8),
              Text('Add to Playlist'),
            ],
          ),
        ),
      ],
      tooltip: 'More actions',
    );
  }

  void _handleTrackInfoTap(BuildContext context, MusicProvider musicProvider) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    // Only expand on small screens
    if (isSmallScreen) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ExpandedMusicPlayer(musicProvider: musicProvider),
      );
    }
  }

  void _handleMenuAction(
    BuildContext context,
    String action,
    MusicProvider musicProvider,
  ) {
    switch (action) {
      case 'stop':
        musicProvider.stopPlayback();
        break;
      case 'queue':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const QueueScreen()));
        break;
      case 'playlist':
        showDialog(
          context: context,
          builder: (context) =>
              SelectPlaylistDialog(track: musicProvider.currentTrack!),
        );
        break;
    }
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
