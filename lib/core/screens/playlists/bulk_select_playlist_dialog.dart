import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../playlists/providers/playlist_provider.dart';

class BulkSelectPlaylistDialog extends StatefulWidget {
  final String title;
  final bool allowCreateNew;

  const BulkSelectPlaylistDialog({
    super.key,
    required this.title,
    this.allowCreateNew = true,
  });

  @override
  State<BulkSelectPlaylistDialog> createState() => _BulkSelectPlaylistDialogState();
}

class _BulkSelectPlaylistDialogState extends State<BulkSelectPlaylistDialog> {
  final _newPlaylistController = TextEditingController();
  bool _isCreatingNew = false;

  @override
  void initState() {
    super.initState();
    // Load playlists when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PlaylistProvider>(context, listen: false).loadPlaylists();
    });
  }

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  Future<void> _createNewPlaylist() async {
    final name = _newPlaylistController.text.trim();
    if (name.isEmpty) return;

    final playlistProvider = Provider.of<PlaylistProvider>(context, listen: false);
    
    setState(() {
      _isCreatingNew = true;
    });

    final success = await playlistProvider.createPlaylist(name: name);
    
    setState(() {
      _isCreatingNew = false;
    });

    if (success && context.mounted) {
      // Return the newly created playlist ID
      final newPlaylist = playlistProvider.playlists.first;
      Navigator.of(context).pop(newPlaylist.id);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create playlist: ${playlistProvider.error}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.6,
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            // Create new playlist section
            if (widget.allowCreateNew) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Create New Playlist',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newPlaylistController,
                              decoration: const InputDecoration(
                                hintText: 'Playlist name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _createNewPlaylist(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isCreatingNew ? null : _createNewPlaylist,
                            child: _isCreatingNew
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Create'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Or select existing playlist:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ],
            
            // Existing playlists list
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
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.playlist_add, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No playlists found'),
                          SizedBox(height: 8),
                          Text('Create a playlist above!'),
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
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: () => Navigator.of(context).pop(playlist.id),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
