import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/models/music.dart';
import '../../playlists/providers/playlist_provider.dart';

class PlaylistSearchTile extends StatelessWidget {
  final PlaylistSearchResult playlist;
  final VoidCallback? onTap;
  final bool showCloneButton;

  const PlaylistSearchTile({
    super.key,
    required this.playlist,
    this.onTap,
    this.showCloneButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: playlist.coverUrl != null
              ? Image.network(
                  playlist.coverUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.queue_music,
                        color: Theme.of(context).primaryColor,
                        size: 24,
                      ),
                    );
                  },
                )
              : Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.queue_music,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'by ${playlist.owner}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.queue_music,
                  size: 12,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  '${playlist.trackCount} tracks',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    playlist.formattedSource,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (playlist.description != null && playlist.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                playlist.description!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: showCloneButton
            ? IconButton(
                icon: const Icon(Icons.copy, color: Colors.blue),
                tooltip: 'Clone playlist',
                onPressed: () => _showCloneDialog(context),
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  void _showCloneDialog(BuildContext context) {
    // Store the root context before showing the dialog
    final rootContext = context;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Clone "${playlist.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will create a copy of this playlist in your library.'),
            const SizedBox(height: 8),
            Text(
              'Source: ${playlist.formattedSource}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            Text(
              'Tracks: ${playlist.trackCount}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Use the root context to avoid context issues
              _clonePlaylist(rootContext);
            },
            child: const Text('Clone'),
          ),
        ],
      ),
    );
  }

  Future<void> _clonePlaylist(BuildContext context) async {
    final playlistProvider = context.read<PlaylistProvider>();
    
    // Store a reference to the navigator to ensure we can always dismiss the dialog
    final navigator = Navigator.of(context);
    bool dialogShown = false;
    
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false, // Prevent back button from dismissing
          child: const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text('Cloning playlist...')),
              ],
            ),
          ),
        ),
      );
      dialogShown = true;

      // Clone the playlist with timeout
      bool success = false;
      try {
        success = await playlistProvider.clonePlaylistFromSearch(playlist).timeout(
          const Duration(minutes: 2),
          onTimeout: () {
            print('Playlist cloning timed out');
            return false;
          },
        );
      } catch (e) {
        print('Error during playlist cloning: $e');
        success = false;
      }
      
      // Always close loading dialog first
      if (dialogShown) {
        try {
          navigator.pop();
          dialogShown = false;
        } catch (e) {
          print('Error dismissing dialog: $e');
        }
      }
      
      // Show result
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success 
                ? 'Playlist cloned successfully!'
                : 'Failed to clone playlist',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Outer catch: Error cloning playlist: $e');
      
      // Always close loading dialog first
      if (dialogShown) {
        try {
          navigator.pop();
          dialogShown = false;
        } catch (dismissError) {
          print('Error dismissing dialog in catch: $dismissError');
        }
      }
      
      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cloning playlist: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
