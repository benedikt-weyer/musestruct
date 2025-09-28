import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../music/providers/saved_tracks_provider.dart';
import '../../../music/providers/music_provider.dart';
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<SavedTracksProvider>().refresh();
            },
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

