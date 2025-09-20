import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/saved_tracks_provider.dart';
import '../providers/queue_provider.dart';
import '../screens/queue/queue_screen.dart';
import '../screens/playlists/select_playlist_dialog.dart';

class MusicPlayerBar extends StatelessWidget {
  const MusicPlayerBar({super.key});

  Color _getSourceColor(String source) {
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
              // Progress bar (clickable)
              GestureDetector(
                onTapDown: (details) async {
                  if (musicProvider.duration.inMilliseconds > 0) {
                    final RenderBox progressBarBox = context.findRenderObject() as RenderBox;
                    final progressBarWidth = progressBarBox.size.width;
                    final tapPosition = details.localPosition.dx;
                    final progress = (tapPosition / progressBarWidth).clamp(0.0, 1.0);
                    final newPosition = Duration(
                      milliseconds: (musicProvider.duration.inMilliseconds * progress).round(),
                    );
                    
                    try {
                      await musicProvider.seekTo(newPosition);
                    } catch (e) {
                      // Show a brief snackbar if seek fails
                      if (context.mounted) {
                        String message = 'Seek not supported for this audio format';
                        if (e.toString().contains('UnsupportedError')) {
                          message = 'Seeking not available for ${musicProvider.currentTrack?.source} tracks on Linux';
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            duration: const Duration(seconds: 3),
                            backgroundColor: Colors.orange,
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
                  child: LinearProgressIndicator(
                    value: musicProvider.duration.inMilliseconds > 0
                        ? musicProvider.position.inMilliseconds / 
                          musicProvider.duration.inMilliseconds
                        : 0,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              
              // Player controls
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  track.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.music_note,
                                      color: Colors.grey[600],
                                    );
                                  },
                                ),
                              )
                            : Icon(
                                Icons.music_note,
                                color: Colors.grey[600],
                              ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Track info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                color: Colors.grey[600],
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
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getSourceColor(track.source).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _getSourceColor(track.source).withOpacity(0.3),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    track.formattedSource,
                                    style: TextStyle(
                                      color: _getSourceColor(track.source),
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
                                      color: Theme.of(context).primaryColor,
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
                      
                      // Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Position info
                          Text(
                            '${_formatDuration(musicProvider.position)} / ${_formatDuration(musicProvider.duration)}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
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
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(
                                    musicProvider.isPlaying 
                                        ? Icons.pause 
                                        : Icons.play_arrow,
                                    size: 32,
                                  ),
                          ),
                          
                          // Stop button
                          IconButton(
                            onPressed: musicProvider.stopPlayback,
                            icon: const Icon(Icons.stop),
                          ),
                          
                          // Play next track button
                          Consumer<QueueProvider>(
                            builder: (context, queueProvider, child) {
                              final hasNextTrack = queueProvider.getNextTrack() != null;
                              return IconButton(
                                onPressed: hasNextTrack && !musicProvider.isLoading
                                    ? musicProvider.playNextTrack
                                    : null,
                                icon: const Icon(Icons.skip_next),
                                tooltip: hasNextTrack ? 'Play next track' : 'No next track',
                              );
                            },
                          ),
                          
                          // Queue button
                          Consumer<QueueProvider>(
                            builder: (context, queueProvider, child) {
                              return Stack(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => const QueueScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.queue_music),
                                    tooltip: 'Queue (${queueProvider.queueLength})',
                                  ),
                                  if (queueProvider.queueLength > 0)
                                    Positioned(
                                      right: 8,
                                      top: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor,
                                          borderRadius: BorderRadius.circular(10),
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
                              );
                            },
                          ),
                          
                          // Save/Remove button
                          Consumer<SavedTracksProvider>(
                            builder: (context, savedTracksProvider, child) {
                              final isSaved = savedTracksProvider.isTrackSaved(
                                musicProvider.currentTrack!.id, 
                                musicProvider.currentTrack!.source
                              );
                              return IconButton(
                                onPressed: () async {
                                  if (isSaved) {
                                    // Find the saved track to remove
                                    final savedTrack = savedTracksProvider.savedTracks
                                        .where((st) => 
                                            st.trackId == musicProvider.currentTrack!.id && 
                                            st.source == musicProvider.currentTrack!.source)
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
                                            content: Text('Removed "${musicProvider.currentTrack!.title}" from saved tracks'),
                                          ),
                                        );
                                      }
                                    }
                                  } else {
                                    final success = await savedTracksProvider.saveTrack(musicProvider.currentTrack!);
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
                                },
                                icon: Icon(
                                  isSaved ? Icons.favorite : Icons.favorite_border,
                                  color: isSaved ? Colors.red : Colors.grey[600],
                                ),
                                tooltip: isSaved ? 'Remove from saved tracks' : 'Add to saved tracks',
                              );
                            },
                          ),
                          
                          // Add to playlist button
                          IconButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => SelectPlaylistDialog(track: musicProvider.currentTrack!),
                              );
                            },
                            icon: const Icon(Icons.playlist_add),
                            tooltip: 'Add to playlist',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
