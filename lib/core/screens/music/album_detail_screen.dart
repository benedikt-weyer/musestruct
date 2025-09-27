import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../music/providers/saved_albums_provider.dart';
import '../../../music/providers/music_provider.dart';
import '../../../queue/providers/queue_provider.dart';
import '../../../music/models/music.dart';
import '../../widgets/track_tile.dart';

class AlbumDetailScreen extends StatefulWidget {
  final SavedAlbum savedAlbum;

  const AlbumDetailScreen({
    super.key,
    required this.savedAlbum,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Track>? _albumTracks;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlbumTracks();
  }

  Future<void> _loadAlbumTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final savedAlbumsProvider = context.read<SavedAlbumsProvider>();
      final tracks = await savedAlbumsProvider.getAlbumTracks(
        widget.savedAlbum.albumId,
        widget.savedAlbum.source,
      );

      setState(() {
        _albumTracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _playAlbum(PlayMode playMode, {bool clearQueue = true}) async {
    if (_albumTracks == null || _albumTracks!.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Album is empty'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final musicProvider = context.read<MusicProvider>();
      final queueProvider = context.read<QueueProvider>();

      // Clear queue if requested
      if (clearQueue) {
        await queueProvider.clearQueue();
        queueProvider.clearPlaylistQueue();
      }

      // Create track order based on play mode
      List<Track> tracksToPlay = List.from(_albumTracks!);
      if (playMode == PlayMode.shuffle) {
        tracksToPlay.shuffle();
      }

      // Play the first track
      await musicProvider.playTrack(tracksToPlay.first, clearQueue: false);

      // Add remaining tracks to queue
      for (int i = 1; i < tracksToPlay.length; i++) {
        await queueProvider.addToQueue(tracksToPlay[i]);
      }

      if (context.mounted) {
        String message;
        if (playMode == PlayMode.shuffle) {
          message = 'Playing album "${widget.savedAlbum.title}" (shuffled, ${tracksToPlay.length} tracks)';
        } else {
          message = 'Playing album "${widget.savedAlbum.title}" (${tracksToPlay.length} tracks)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play album: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _addAlbumToQueue(PlayMode playMode) async {
    if (_albumTracks == null || _albumTracks!.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Album is empty'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final queueProvider = context.read<QueueProvider>();

      // Create track list and shuffle if needed
      List<Track> tracksToAdd = List.from(_albumTracks!);
      if (playMode == PlayMode.shuffle) {
        tracksToAdd.shuffle();
      }

      // Add each track to the queue
      int successCount = 0;
      for (final track in tracksToAdd) {
        final success = await queueProvider.addToQueue(track);
        if (success) successCount++;
      }

      if (context.mounted) {
        final message = successCount == tracksToAdd.length
            ? 'Added all ${successCount} tracks to queue'
            : 'Added ${successCount}/${tracksToAdd.length} tracks to queue';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: successCount == tracksToAdd.length ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add album to queue: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.savedAlbum.title),
        actions: [
          if (_albumTracks != null && _albumTracks!.isNotEmpty) ...[
            // Add to queue button
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_to_photos),
              onSelected: (value) {
                switch (value) {
                  case 'add_normal':
                    _addAlbumToQueue(PlayMode.normal);
                    break;
                  case 'add_shuffle':
                    _addAlbumToQueue(PlayMode.shuffle);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'add_normal',
                  child: Row(
                    children: [
                      Icon(Icons.queue_music),
                      SizedBox(width: 8),
                      Text('Add to Queue'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'add_shuffle',
                  child: Row(
                    children: [
                      Icon(Icons.shuffle),
                      SizedBox(width: 8),
                      Text('Add to Queue (Shuffle)'),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAlbumTracks,
            ),
          ],
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _albumTracks != null && _albumTracks!.isNotEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Shuffle play button
                FloatingActionButton(
                  heroTag: "shuffle",
                  onPressed: () => _playAlbum(PlayMode.shuffle),
                  backgroundColor: Colors.orange,
                  child: const Icon(Icons.shuffle),
                ),
                const SizedBox(height: 8),
                // Normal play button
                FloatingActionButton(
                  heroTag: "play",
                  onPressed: () => _playAlbum(PlayMode.normal),
                  child: const Icon(Icons.play_arrow),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
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
              'Error loading album tracks',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAlbumTracks,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_albumTracks == null || _albumTracks!.isEmpty) {
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
              'No tracks found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'This album appears to be empty',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Album header
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: widget.savedAlbum.coverUrl != null
                    ? Image.network(
                        widget.savedAlbum.coverUrl!,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 120,
                          height: 120,
                          color: Colors.grey[300],
                          child: const Icon(Icons.album, size: 40),
                        ),
                      )
                    : Container(
                        width: 120,
                        height: 120,
                        color: Colors.grey[300],
                        child: const Icon(Icons.album, size: 40),
                      ),
              ),
              const SizedBox(width: 16),
              // Album info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.savedAlbum.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.savedAlbum.artist,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.savedAlbum.releaseDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.savedAlbum.releaseDate!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${_albumTracks!.length} track${_albumTracks!.length != 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Source: ${widget.savedAlbum.source.toUpperCase()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        // Track list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _albumTracks!.length,
            itemBuilder: (context, index) {
              final track = _albumTracks![index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: TrackTile(
                  track: track,
                  showTrackNumber: true,
                  trackNumber: index + 1,
                  onTap: () async {
                    final musicProvider = context.read<MusicProvider>();
                    try {
                      await musicProvider.playTrack(track);
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Playing "${track.title}"'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to play track: $e'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  showSaveButton: true,
                  showQueueButton: true,
                  showPlaylistButton: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AlbumDetailContent extends StatelessWidget {
  final SavedAlbum savedAlbum;

  const AlbumDetailContent({super.key, required this.savedAlbum});

  @override
  Widget build(BuildContext context) {
    // Just return the original screen for now - the BaseLayout will handle the persistent elements
    return AlbumDetailScreen(savedAlbum: savedAlbum);
  }
}
