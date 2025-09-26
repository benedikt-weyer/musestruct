import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../playlists/providers/playlist_provider.dart';
import '../../../queue/providers/queue_provider.dart';
import '../../../music/providers/music_provider.dart';
import '../../../playlists/models/playlist.dart';
import '../../../music/models/music.dart';
import '../../providers/navigation_provider.dart';
import 'create_playlist_dialog.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreatePlaylistDialog,
          ),
        ],
      ),
      body: Consumer<PlaylistProvider>(
        builder: (context, playlistProvider, child) {
          if (playlistProvider.isLoading && playlistProvider.playlists.isEmpty) {
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
                    'Error loading playlists',
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
                    onPressed: () => playlistProvider.loadPlaylists(),
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
                  Icon(
                    Icons.queue_music_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No playlists yet',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first playlist to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showCreatePlaylistDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Playlist'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => playlistProvider.loadPlaylists(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: playlistProvider.playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlistProvider.playlists[index];
                return PlaylistTile(
                  playlist: playlist,
                  onTap: () => _navigateToPlaylistDetail(playlist),
                  onEdit: () => _showEditPlaylistDialog(playlist),
                  onDelete: () => _showDeletePlaylistDialog(playlist),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePlaylistDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Playlists'),
        content: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Enter playlist name...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _searchController.clear();
              context.read<PlaylistProvider>().clearSearch();
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              final query = _searchController.text.trim();
              if (query.isNotEmpty) {
                context.read<PlaylistProvider>().searchPlaylists(query);
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    showDialog(
      context: context,
      builder: (context) => const CreatePlaylistDialog(),
    );
  }

  void _showEditPlaylistDialog(Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => CreatePlaylistDialog(
        playlist: playlist,
        isEdit: true,
      ),
    );
  }

  void _showDeletePlaylistDialog(Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<PlaylistProvider>().deletePlaylist(playlist.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _navigateToPlaylistDetail(Playlist playlist) {
    context.read<NavigationProvider>().navigateToPlaylistDetail(
      playlist.id,
      playlist,
    );
  }
}

class PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const PlaylistTile({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
          child: Icon(
            Icons.queue_music,
            color: Theme.of(context).primaryColor,
          ),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (playlist.description != null && playlist.description!.isNotEmpty)
              Text(
                playlist.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  playlist.isPublic ? Icons.public : Icons.lock,
                  size: 12,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  '${playlist.itemCount} items',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play button
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => _playPlaylist(context, playlist, PlayMode.normal),
              tooltip: 'Play Playlist',
            ),
            // Shuffle button
            IconButton(
              icon: const Icon(Icons.shuffle),
              onPressed: () => _playPlaylist(context, playlist, PlayMode.shuffle),
              tooltip: 'Shuffle Playlist',
            ),
            // Menu button
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                    break;
                  case 'delete':
                    onDelete();
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
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Future<void> _playPlaylist(BuildContext context, Playlist playlist, PlayMode playMode) async {
    try {
      // Get playlist items to create track order
      final playlistProvider = context.read<PlaylistProvider>();
      final queueProvider = context.read<QueueProvider>();
      
      // Load playlist items
      await playlistProvider.loadPlaylistItems(playlist.id);
      
      if (playlistProvider.currentPlaylistItems.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Playlist is empty'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
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
              behavior: SnackBarBehavior.floating,
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
        playlistId: playlist.id,
        playlistName: playlist.name,
        playlistDescription: playlist.description,
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing playlist: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
