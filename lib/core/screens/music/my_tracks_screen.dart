import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../music/providers/saved_tracks_provider.dart';
import '../../../music/providers/music_provider.dart';
import '../../../queue/providers/queue_provider.dart';
import '../../../music/models/music.dart';
import '../../widgets/track_tile.dart';

class MyTracksScreen extends StatefulWidget {
  const MyTracksScreen({super.key});

  @override
  State<MyTracksScreen> createState() => _MyTracksScreenState();
}

class _MyTracksScreenState extends State<MyTracksScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SavedTracksProvider>().loadSavedTracks();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      // Load more when we're 200 pixels from the bottom
      context.read<SavedTracksProvider>().loadMoreTracks();
    }
  }

  Future<void> _playAllTracks(PlayMode playMode, {bool clearQueue = true}) async {
    try {
      final savedTracksProvider = context.read<SavedTracksProvider>();
      final queueProvider = context.read<QueueProvider>();
      final musicProvider = context.read<MusicProvider>();
      
      if (savedTracksProvider.savedTracks.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No saved tracks to play'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
        return;
      }

      // Clear queue if requested (default behavior)
      if (clearQueue) {
        await queueProvider.clearQueue();
        queueProvider.clearPlaylistQueue();
      }

      // Convert saved tracks to tracks and create track order
      final tracks = savedTracksProvider.savedTracks.map((savedTrack) => savedTrack.toTrack()).toList();
      List<String> trackOrder = tracks.map((track) => track.id).toList();

      if (playMode == PlayMode.shuffle) {
        trackOrder.shuffle();
      }

      // Get the first track based on the (possibly shuffled) track order
      final firstTrackId = trackOrder.first;
      final firstTrack = tracks.firstWhere((track) => track.id == firstTrackId);
      
      // Add "My Tracks" as a playlist to queue
      final success = await queueProvider.addPlaylistToQueue(
        playlistId: 'saved_tracks',
        playlistName: 'My Tracks',
        playlistDescription: 'Your saved tracks',
        coverUrl: null,
        playMode: playMode,
        loopMode: LoopMode.once,
        trackOrder: trackOrder,
        currentTrackId: firstTrack.id,
        currentTrackTitle: firstTrack.title,
        currentTrackArtist: firstTrack.artist,
        currentTrackAlbum: firstTrack.album,
        currentTrackDuration: firstTrack.duration,
        currentTrackSource: firstTrack.source,
        currentTrackCoverUrl: firstTrack.coverUrl,
      );

      if (success) {
        // Start playing the first track
        await musicProvider.playTrack(firstTrack, clearQueue: false);
        
        if (context.mounted) {
          final message = playMode == PlayMode.shuffle 
              ? 'Playing all tracks (shuffled)'
              : 'Playing all tracks';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play tracks: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<SavedTracksProvider>(
          builder: (context, provider, child) {
            final totalTracks = provider.totalTracks ?? 0;
            final loadedTracks = provider.currentTrackCount;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('My Tracks'),
                if (totalTracks > 0)
                  Text(
                    totalTracks == loadedTracks 
                        ? '$totalTracks track${totalTracks != 1 ? 's' : ''}'
                        : '$loadedTracks of $totalTracks tracks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[300],
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          // Play all button
          Consumer<SavedTracksProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: provider.savedTracks.isNotEmpty 
                    ? () => _playAllTracks(PlayMode.normal)
                    : null,
                tooltip: 'Play All',
              );
            },
          ),
          // Shuffle button
          Consumer<SavedTracksProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: const Icon(Icons.shuffle),
                onPressed: provider.savedTracks.isNotEmpty 
                    ? () => _playAllTracks(PlayMode.shuffle)
                    : null,
                tooltip: 'Shuffle All',
              );
            },
          ),
          // More options menu
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  context.read<SavedTracksProvider>().refresh();
                  break;
                case 'play_keep_queue':
                  _playAllTracks(PlayMode.normal, clearQueue: false);
                  break;
                case 'shuffle_keep_queue':
                  _playAllTracks(PlayMode.shuffle, clearQueue: false);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 8),
                    Text('Refresh'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'play_keep_queue',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add, size: 20),
                    SizedBox(width: 8),
                    Text('Add All to Queue'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'shuffle_keep_queue',
                child: Row(
                  children: [
                    Icon(Icons.shuffle, size: 20),
                    SizedBox(width: 8),
                    Text('Add All to Queue (Shuffle)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<SavedTracksProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.savedTracks.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.error != null) {
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
                    'Error loading saved tracks',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      provider.clearError();
                      provider.refresh();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (provider.savedTracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved tracks yet',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Save tracks from search results to see them here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await provider.loadSavedTracks(reset: true);
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: provider.savedTracks.length + (provider.isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                // Show loading indicator at the end
                if (index >= provider.savedTracks.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final savedTrack = provider.savedTracks[index];
                final track = savedTrack.toTrack();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: TrackTile(
                    track: track,
                    showTrackNumber: true,
                    trackNumber: index + 1,
                    onTap: () async {
                      try {
                        await context.read<MusicProvider>().playTrack(track); // Default clears queue
                        
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Playing "${track.title}"'),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
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
                              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
                            ),
                          );
                        }
                      }
                    },
                    showSaveButton: true,
                    showQueueButton: true,
                    showPlaylistButton: true,
                    showRemoveButton: true,
                    onRemove: () async {
                      final success = await provider.removeSavedTrack(
                        savedTrack.id,
                        savedTrack.trackId,
                        savedTrack.source,
                      );
                      
                      if (success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Removed "${savedTrack.title}" from saved tracks'),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () {
                                // TODO: Implement undo functionality
                              },
                            ),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

