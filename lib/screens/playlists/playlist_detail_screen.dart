import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/queue_provider.dart';
import '../../models/playlist.dart';
import '../../models/music.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/music_player_bar.dart';
import 'add_to_playlist_dialog.dart';
import 'create_playlist_dialog.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().loadPlaylistItems(widget.playlist.id);
    });
  }

  Future<void> _playPlaylist(PlayMode playMode) async {
    try {
      final playlistProvider = context.read<PlaylistProvider>();
      final queueProvider = context.read<QueueProvider>();
      
      if (playlistProvider.currentPlaylistItems.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Playlist is empty'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Get track items and create track order
      final trackItems = playlistProvider.currentPlaylistItems
          .where((item) => !item.isPlaylist) // Only tracks for now
          .toList();

      if (trackItems.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Playlist is empty'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Create track order based on play mode
      List<String> trackOrder = trackItems.map((item) => item.itemId).toList();

      if (playMode == PlayMode.shuffle) {
        trackOrder.shuffle();
      }

      // Get the first track item for current track details
      final firstTrackItem = trackItems.first;
      
      // Add playlist to queue with current track details
      final success = await queueProvider.addPlaylistToQueue(
        playlistId: widget.playlist.id,
        playlistName: widget.playlist.name,
        playlistDescription: widget.playlist.description,
        coverUrl: null, // TODO: Add cover URL support
        playMode: playMode,
        loopMode: LoopMode.once,
        trackOrder: trackOrder,
        currentTrackId: firstTrackItem.itemId,
        currentTrackTitle: firstTrackItem.title,
        currentTrackArtist: firstTrackItem.artist,
        currentTrackAlbum: firstTrackItem.album,
        currentTrackDuration: firstTrackItem.duration,
        currentTrackSource: firstTrackItem.source,
        currentTrackCoverUrl: firstTrackItem.coverUrl,
      );

      if (success) {
        // Start playing the first track from the playlist
        final musicProvider = context.read<MusicProvider>();
        
        // Create track from playlist item data
        final track = Track(
          id: firstTrackItem.itemId,
          title: firstTrackItem.title ?? 'Unknown Title',
          artist: firstTrackItem.artist ?? 'Unknown Artist',
          album: firstTrackItem.album ?? 'Unknown Album',
          duration: firstTrackItem.duration,
          coverUrl: firstTrackItem.coverUrl,
          source: firstTrackItem.source ?? 'qobuz',
        );
        
        await musicProvider.playTrack(track);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success 
                ? 'Playing playlist'
                : 'Failed to add playlist to queue',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing playlist: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          // Play button
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () => _playPlaylist(PlayMode.normal),
            tooltip: 'Play Playlist',
          ),
          // Shuffle button
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: () => _playPlaylist(PlayMode.shuffle),
            tooltip: 'Shuffle Playlist',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddItemDialog,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _showEditDialog();
                  break;
                case 'delete':
                  _showDeleteDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 8),
                    Text('Edit Playlist'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Playlist', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Consumer<PlaylistProvider>(
                  builder: (context, playlistProvider, child) {
                    if (playlistProvider.isLoading && playlistProvider.currentPlaylistItems.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

          if (playlistProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading playlist',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    playlistProvider.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => playlistProvider.loadPlaylistItems(widget.playlist.id),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (playlistProvider.currentPlaylistItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.queue_music_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Empty Playlist',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add tracks or other playlists to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showAddItemDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Items'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Playlist info header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                      child: Icon(
                        Icons.queue_music,
                        size: 30,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlistProvider.currentPlaylist?.name ?? widget.playlist.name,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (playlistProvider.currentPlaylist?.description != null &&
                              playlistProvider.currentPlaylist!.description!.isNotEmpty)
                            Text(
                              playlistProvider.currentPlaylist!.description!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                playlistProvider.currentPlaylist?.isPublic ?? widget.playlist.isPublic
                                    ? Icons.public
                                    : Icons.lock,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${playlistProvider.currentPlaylistItems.length} items',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
              // Items list
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => playlistProvider.loadPlaylistItems(widget.playlist.id),
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: playlistProvider.currentPlaylistItems.length,
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final item = playlistProvider.currentPlaylistItems[oldIndex];
                      playlistProvider.reorderPlaylistItem(
                        playlistId: widget.playlist.id,
                        itemId: item.id,
                        newPosition: newIndex,
                      );
                    },
                    itemBuilder: (context, index) {
                      final item = playlistProvider.currentPlaylistItems[index];
                      return PlaylistItemTile(
                        key: ValueKey(item.id),
                        item: item,
                        onRemove: () => _removeItem(item),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
                  },
                ),
              ),
            ],
          ),
          // Music player bar at the bottom
          Consumer<MusicProvider>(
            builder: (context, musicProvider, child) {
              if (musicProvider.currentTrack != null) {
                return const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MusicPlayerBar(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 2, // Playlists tab is selected
        onTap: (index) {
          switch (index) {
            case 0:
              // Go back to home screen and switch to search tab
              Navigator.of(context).popUntil((route) => route.isFirst);
              break;
            case 1:
              // Go back to home screen and switch to my tracks tab
              Navigator.of(context).popUntil((route) => route.isFirst);
              break;
            case 2:
              // Stay in playlists - just go back to playlists list
              Navigator.of(context).pop();
              break;
            case 3:
              // Go back to home screen and switch to settings tab
              Navigator.of(context).popUntil((route) => route.isFirst);
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'My Tracks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play),
            label: 'Playlists',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (context) => AddToPlaylistDialog(
        playlistId: widget.playlist.id,
        onItemAdded: () {
          context.read<PlaylistProvider>().loadPlaylistItems(widget.playlist.id);
        },
      ),
    );
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) => CreatePlaylistDialog(
        playlist: context.read<PlaylistProvider>().currentPlaylist ?? widget.playlist,
        isEdit: true,
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${widget.playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<PlaylistProvider>().deletePlaylist(widget.playlist.id);
              Navigator.of(context).pop(); // Go back to playlists list
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _removeItem(PlaylistItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "${item.displayTitle}" from this playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<PlaylistProvider>().removeItemFromPlaylist(
                widget.playlist.id,
                item.id,
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class PlaylistItemTile extends StatelessWidget {
  final PlaylistItem item;
  final VoidCallback onRemove;

  const PlaylistItemTile({
    super.key,
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isPlaylist) {
      // Show playlist item
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue.withOpacity(0.1),
            child: const Icon(Icons.queue_music, color: Colors.blue),
          ),
          title: Text(
            item.displayTitle,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: const Text('Playlist'),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            onPressed: onRemove,
          ),
          onTap: () => _navigateToPlaylist(context),
        ),
      );
    } else {
      // Show track item using TrackTile
      final track = _createTrackFromItem();
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: TrackTile(
          track: track,
          onTap: () => _playTrack(context),
          showSaveButton: true,
          showQueueButton: true,
          showPlaylistButton: false,
          showRemoveButton: true,
          onRemove: onRemove,
        ),
      );
    }
  }

  Track _createTrackFromItem() {
    return Track(
      id: item.itemId,
      title: item.title ?? 'Unknown Title',
      artist: item.artist ?? 'Unknown Artist',
      album: item.album ?? 'Unknown Album',
      duration: item.duration,
      source: item.source ?? 'unknown',
      coverUrl: item.coverUrl,
    );
  }

  void _navigateToPlaylist(BuildContext context) {
    // TODO: Navigate to the nested playlist
    // For now, just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nested playlists not yet implemented')),
    );
  }

  void _playTrack(BuildContext context) {
    final track = _createTrackFromItem();
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    musicProvider.playTrack(track);
  }
}
