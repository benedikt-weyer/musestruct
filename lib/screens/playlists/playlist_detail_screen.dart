import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/playlist_provider.dart';
import '../../models/playlist.dart';
import '../../models/music.dart';
import '../../widgets/track_tile.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
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
      body: Consumer<PlaylistProvider>(
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.isPlaylist
              ? Colors.blue.withOpacity(0.1)
              : Colors.green.withOpacity(0.1),
          child: Icon(
            item.isPlaylist ? Icons.queue_music : Icons.music_note,
            color: item.isPlaylist ? Colors.blue : Colors.green,
          ),
        ),
        title: Text(
          item.displayTitle,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.displaySubtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            if (item.duration != null && !item.isPlaylist)
              Text(
                item.formattedDuration,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          onPressed: onRemove,
        ),
        onTap: () {
          // TODO: Handle tap - play track or navigate to playlist
        },
      ),
    );
  }
}
