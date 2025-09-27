import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../music/models/music.dart';
import '../../../playlists/models/playlist.dart';
import '../../../playlists/providers/playlist_provider.dart';

class SelectPlaylistForAlbumDialog extends StatefulWidget {
  final List<Track> tracks;
  final String albumTitle;

  const SelectPlaylistForAlbumDialog({
    super.key, 
    required this.tracks,
    required this.albumTitle,
  });

  @override
  State<SelectPlaylistForAlbumDialog> createState() => _SelectPlaylistForAlbumDialogState();
}

class _SelectPlaylistForAlbumDialogState extends State<SelectPlaylistForAlbumDialog> {
  bool _isAddingTracks = false;

  @override
  void initState() {
    super.initState();
    // Load playlists when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PlaylistProvider>(context, listen: false).loadPlaylists();
    });
  }

  Future<void> _addAlbumToPlaylist(Playlist playlist) async {
    if (_isAddingTracks) return; // Prevent multiple submissions
    
    setState(() {
      _isAddingTracks = true;
    });

    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
    
    int successCount = 0;
    int totalTracks = widget.tracks.length;

    // Add each track to the playlist
    for (final track in widget.tracks) {
      final success = await playlistProvider.addTrackToPlaylist(
        playlistId: playlist.id,
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        source: track.source,
        coverUrl: track.coverUrl,
      );
      
      if (success) {
        successCount++;
      }
    }

    setState(() {
      _isAddingTracks = false;
    });

    if (context.mounted) {
      String message;
      Color backgroundColor;
      
      if (successCount == totalTracks) {
        message = 'Added all ${totalTracks} tracks from "${widget.albumTitle}" to "${playlist.name}"';
        backgroundColor = Colors.green;
      } else if (successCount > 0) {
        message = 'Added ${successCount} of ${totalTracks} tracks from "${widget.albumTitle}" to "${playlist.name}"';
        backgroundColor = Colors.orange;
      } else {
        message = 'Failed to add tracks from "${widget.albumTitle}" to "${playlist.name}"';
        backgroundColor = Colors.red;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      
      if (successCount > 0) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add "${widget.albumTitle}" to Playlist'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.6,
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            // Album info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.album,
                    size: 40,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.albumTitle,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${widget.tracks.length} track${widget.tracks.length != 1 ? 's' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Playlist list
            Expanded(
              child: Consumer<PlaylistProvider>(
                builder: (context, playlistProvider, child) {
                  if (playlistProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (playlistProvider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error, size: 48, color: Colors.red[300]),
                          const SizedBox(height: 16),
                          Text('Error: ${playlistProvider.error}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              playlistProvider.loadPlaylists();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  if (playlistProvider.playlists.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.playlist_add, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text('No playlists found'),
                          const SizedBox(height: 8),
                          const Text('Create a playlist first!'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              // TODO: Open create playlist dialog
                            },
                            child: const Text('Create Playlist'),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    itemCount: playlistProvider.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlistProvider.playlists[index];
                      return ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: Text(playlist.name),
                        subtitle: Text('${playlist.itemCount} items'),
                        trailing: _isAddingTracks
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => _addAlbumToPlaylist(playlist),
                              ),
                        onTap: _isAddingTracks
                            ? null
                            : () => _addAlbumToPlaylist(playlist),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isAddingTracks ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
