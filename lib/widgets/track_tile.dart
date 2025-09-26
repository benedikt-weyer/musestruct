import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/music.dart';
import '../music/providers/saved_tracks_provider.dart';
import '../queue/providers/queue_provider.dart';
import '../screens/playlists/select_playlist_dialog.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool isPlaying;
  final bool isLoading;
  final bool showSaveButton;
  final bool showQueueButton;
  final bool showPlaylistButton;
  final bool showRemoveButton;
  final VoidCallback? onRemove;

  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.isPlaying = false,
    this.isLoading = false,
    this.showSaveButton = true,
    this.showQueueButton = true,
    this.showPlaylistButton = false,
    this.showRemoveButton = false,
    this.onRemove,
  });

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
    return ListTile(
      leading: Stack(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[300],
            ),
            child: track.coverUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
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
          if (isLoading)
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.black54,
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (isPlaying && !isLoading)
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.black54,
              ),
              child: const Icon(
                Icons.volume_up,
                color: Colors.white,
              ),
            ),
        ],
      ),
      title: Text(
        track.title,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
          color: isPlaying ? Theme.of(context).primaryColor : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying 
                  ? Theme.of(context).primaryColor.withOpacity(0.7)
                  : Colors.grey[600],
            ),
          ),
          Text(
            track.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
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
              // Audio quality info
              if (track.formattedQuality.isNotEmpty) ...[
                const SizedBox(width: 6),
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
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Duration text (if available)
          if (track.duration != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                track.formattedDuration,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ),
          // Quality badge (if available)
          if (track.quality != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  track.quality!.toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // Buttons
          if (showQueueButton)
            IconButton(
              icon: Consumer<QueueProvider>(
                builder: (context, queueProvider, child) {
                  return queueProvider.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.queue_music, size: 20);
                },
              ),
              onPressed: () async {
                final queueProvider = Provider.of<QueueProvider>(context, listen: false);
                if (queueProvider.isLoading) return;
                
                final success = await queueProvider.addToQueue(track);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success 
                          ? 'Added "${track.title}" to queue'
                          : 'Failed to add track to queue',
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              tooltip: 'Add to queue',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              iconSize: 20,
            ),
          if (showSaveButton)
            IconButton(
              icon: Consumer<SavedTracksProvider>(
                builder: (context, savedTracksProvider, child) {
                  final isSaved = savedTracksProvider.isTrackSaved(track.id, track.source);
                  return Icon(
                    isSaved ? Icons.favorite : Icons.favorite_border,
                    color: isSaved ? Colors.red : Colors.grey[600],
                    size: 20,
                  );
                },
              ),
              onPressed: () async {
                final savedTracksProvider = Provider.of<SavedTracksProvider>(context, listen: false);
                final isSaved = savedTracksProvider.isTrackSaved(track.id, track.source);
                
                if (isSaved) {
                  // Find the saved track to remove
                  final savedTrack = savedTracksProvider.savedTracks
                      .where((st) => st.trackId == track.id && st.source == track.source)
                      .firstOrNull;
                  if (savedTrack != null) {
                    await savedTracksProvider.removeSavedTrack(
                      savedTrack.id,
                      track.id,
                      track.source,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Removed "${track.title}" from saved tracks'),
                        ),
                      );
                    }
                  }
                } else {
                  final success = await savedTracksProvider.saveTrack(track);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success 
                            ? 'Added "${track.title}" to saved tracks'
                            : 'Failed to save track',
                        ),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                }
              },
              tooltip: 'Toggle saved track',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              iconSize: 20,
            ),
          if (showPlaylistButton)
            IconButton(
              icon: const Icon(Icons.playlist_add, size: 20),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => SelectPlaylistDialog(track: track),
                );
              },
              tooltip: 'Add to playlist',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              iconSize: 20,
            ),
          if (showRemoveButton)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
              onPressed: onRemove,
              tooltip: 'Remove from playlist',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              iconSize: 20,
            ),
        ],
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
