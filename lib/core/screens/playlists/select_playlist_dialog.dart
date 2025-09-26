import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/music.dart';
import '../../../models/playlist.dart';
import '../../../playlists/providers/playlist_provider.dart';

class SelectPlaylistDialog extends StatefulWidget {
  final Track track;

  const SelectPlaylistDialog({super.key, required this.track});

  @override
  State<SelectPlaylistDialog> createState() => _SelectPlaylistDialogState();
}

class _SelectPlaylistDialogState extends State<SelectPlaylistDialog> {
  @override
  void initState() {
    super.initState();
    // Load playlists when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PlaylistProvider>(context, listen: false).loadPlaylists();
    });
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
    
    final success = await playlistProvider.addTrackToPlaylist(
      playlistId: playlist.id,
      trackId: widget.track.id,
      title: widget.track.title,
      artist: widget.track.artist,
      album: widget.track.album,
      duration: widget.track.duration,
      source: widget.track.source,
      coverUrl: widget.track.coverUrl,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Added "${widget.track.title}" to "${playlist.name}"'
              : 'Failed to add track to playlist'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      
      if (success) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add "${widget.track.title}" to Playlist'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.6,
        height: MediaQuery.of(context).size.height * 0.5,
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
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addToPlaylist(playlist),
                  ),
                  onTap: () => _addToPlaylist(playlist),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
