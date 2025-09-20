import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/saved_tracks_provider.dart';
import '../../providers/music_provider.dart';
import '../../models/music.dart';
import '../../widgets/track_tile.dart';
import '../playlists/select_playlist_dialog.dart';

class MyTracksScreen extends StatefulWidget {
  const MyTracksScreen({super.key});

  @override
  State<MyTracksScreen> createState() => _MyTracksScreenState();
}

class _MyTracksScreenState extends State<MyTracksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SavedTracksProvider>().loadSavedTracks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tracks'),
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
              await provider.loadSavedTracks();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.savedTracks.length,
              itemBuilder: (context, index) {
                final savedTrack = provider.savedTracks[index];
                final track = savedTrack.toTrack();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: TrackTile(
                    track: track,
                    onTap: () async {
                      try {
                        await context.read<MusicProvider>().playTrack(track);
                        
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Playing "${track.title}"'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to play track: $e'),
                              backgroundColor: Colors.red,
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

