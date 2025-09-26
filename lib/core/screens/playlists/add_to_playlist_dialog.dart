import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../playlists/providers/playlist_provider.dart';
import '../../../music/providers/music_provider.dart';
import '../../../playlists/models/playlist.dart';
import '../../../music/models/music.dart';

class AddToPlaylistDialog extends StatefulWidget {
  final String playlistId;
  final VoidCallback onItemAdded;

  const AddToPlaylistDialog({
    super.key,
    required this.playlistId,
    required this.onItemAdded,
  });

  @override
  State<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<AddToPlaylistDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add),
                  const SizedBox(width: 8),
                  const Text(
                    'Add to Playlist',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search tracks or playlists...',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.clear),
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Tracks', icon: Icon(Icons.music_note)),
                Tab(text: 'Playlists', icon: Icon(Icons.queue_music)),
              ],
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _TracksTab(
                    searchQuery: _searchQuery,
                    onTrackSelected: (track) => _addTrackToPlaylist(track),
                  ),
                  _PlaylistsTab(
                    searchQuery: _searchQuery,
                    onPlaylistSelected: (playlist) => _addPlaylistToPlaylist(playlist),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTrackToPlaylist(Track track) async {
    final playlistProvider = context.read<PlaylistProvider>();
    final success = await playlistProvider.addItemToPlaylist(
      playlistId: widget.playlistId,
      itemType: 'track',
      itemId: track.id,
    );

    if (mounted) {
      if (success) {
        widget.onItemAdded();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${track.title}" to playlist'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(playlistProvider.error ?? 'Failed to add track'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _addPlaylistToPlaylist(Playlist playlist) async {
    final playlistProvider = context.read<PlaylistProvider>();
    final success = await playlistProvider.addItemToPlaylist(
      playlistId: widget.playlistId,
      itemType: 'playlist',
      itemId: playlist.id,
    );

    if (mounted) {
      if (success) {
        widget.onItemAdded();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${playlist.name}" to playlist'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(playlistProvider.error ?? 'Failed to add playlist'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _TracksTab extends StatefulWidget {
  final String searchQuery;
  final Function(Track) onTrackSelected;

  const _TracksTab({
    required this.searchQuery,
    required this.onTrackSelected,
  });

  @override
  State<_TracksTab> createState() => _TracksTabState();
}

class _TracksTabState extends State<_TracksTab> {
  @override
  void initState() {
    super.initState();
    // Load some sample tracks or search results
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.searchQuery.isNotEmpty) {
        context.read<MusicProvider>().searchMusic(widget.searchQuery);
      }
    });
  }

  @override
  void didUpdateWidget(_TracksTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery && widget.searchQuery.isNotEmpty) {
      context.read<MusicProvider>().searchMusic(widget.searchQuery);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        if (musicProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (musicProvider.searchResults?.tracks.isEmpty ?? true) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.searchQuery.isEmpty
                      ? 'Search for tracks to add'
                      : 'No tracks found',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.searchQuery.isEmpty
                      ? 'Enter a search term to find tracks'
                      : 'Try a different search term',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: musicProvider.searchResults?.tracks.length ?? 0,
          itemBuilder: (context, index) {
            final track = musicProvider.searchResults!.tracks[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.1),
                child: const Icon(Icons.music_note, color: Colors.green),
              ),
              title: Text(track.title),
              subtitle: Text('${track.artist} • ${track.album}'),
              trailing: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => widget.onTrackSelected(track),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  final String searchQuery;
  final Function(Playlist) onPlaylistSelected;

  const _PlaylistsTab({
    required this.searchQuery,
    required this.onPlaylistSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, playlistProvider, child) {
        // Filter playlists based on search query
        final filteredPlaylists = playlistProvider.playlists.where((playlist) {
          if (searchQuery.isEmpty) return true;
          return playlist.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
              (playlist.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        }).toList();

        if (filteredPlaylists.isEmpty) {
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
                  searchQuery.isEmpty
                      ? 'No playlists available'
                      : 'No playlists found',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  searchQuery.isEmpty
                      ? 'Create a playlist first'
                      : 'Try a different search term',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredPlaylists.length,
          itemBuilder: (context, index) {
            final playlist = filteredPlaylists[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.withOpacity(0.1),
                child: const Icon(Icons.queue_music, color: Colors.blue),
              ),
              title: Text(playlist.name),
              subtitle: Text(
                playlist.description ?? '${playlist.itemCount} items',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => onPlaylistSelected(playlist),
              ),
            );
          },
        );
      },
    );
  }
}
