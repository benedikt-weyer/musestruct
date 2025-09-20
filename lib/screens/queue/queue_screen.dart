import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/queue_provider.dart';
import '../../providers/music_provider.dart';
import '../../models/music.dart';
import '../../widgets/track_tile.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          Consumer<QueueProvider>(
            builder: (context, queueProvider, child) {
              return IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed: queueProvider.queue.isEmpty || queueProvider.isLoading
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Clear Queue'),
                            content: const Text('Are you sure you want to clear all tracks from the queue?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirmed == true) {
                          final success = await queueProvider.clearQueue();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success 
                                    ? 'Queue cleared'
                                    : 'Failed to clear queue',
                                ),
                                backgroundColor: success ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        }
                      },
                tooltip: 'Clear Queue',
              );
            },
          ),
        ],
      ),
      body: Consumer<QueueProvider>(
        builder: (context, queueProvider, child) {
          if (queueProvider.isLoading && queueProvider.queue.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (queueProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading queue',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    queueProvider.error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => queueProvider.refreshQueue(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (queueProvider.queue.isEmpty && queueProvider.playlistQueue.isEmpty) {
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
                    'Queue is empty',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add tracks or playlists to your queue to see them here',
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
              // Now Playing section
              Consumer<MusicProvider>(
                builder: (context, musicProvider, child) {
                  if (musicProvider.currentTrack == null) {
                    return const SizedBox.shrink();
                  }
                  
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).primaryColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.play_circle_filled,
                              color: Theme.of(context).primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Now Playing',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TrackTile(
                          track: musicProvider.currentTrack!,
                          isPlaying: musicProvider.isPlaying,
                          isLoading: musicProvider.isLoading,
                          showSaveButton: true,
                          showQueueButton: false,
                          showPlaylistButton: true,
                          onTap: () async {
                            await musicProvider.togglePlayPause();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Queue items
              Expanded(
                child: _buildQueueItems(queueProvider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQueueItems(QueueProvider queueProvider) {
    // Combine regular queue items and playlist queue items
    final List<Widget> queueItems = [];
    
    // Add playlist queue items first
    for (int i = 0; i < queueProvider.playlistQueue.length; i++) {
      final playlistItem = queueProvider.playlistQueue[i];
      queueItems.add(
        _buildPlaylistQueueItem(playlistItem, i),
      );
    }
    
    // Add regular queue items
    for (int i = 0; i < queueProvider.queue.length; i++) {
      final queueItem = queueProvider.queue[i];
      final track = queueItem.toTrack();
      queueItems.add(
        _buildTrackQueueItem(queueItem, track, i + queueProvider.playlistQueue.length),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: queueItems.length,
      itemBuilder: (context, index) => queueItems[index],
    );
  }

  Widget _buildPlaylistQueueItem(PlaylistQueueItem playlistItem, int index) {
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
          playlistItem.playlistName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${playlistItem.trackOrder.length} tracks • ${playlistItem.playMode.name} • ${playlistItem.loopMode.name}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            if (playlistItem.playlistDescription != null && playlistItem.playlistDescription!.isNotEmpty)
              Text(
                playlistItem.playlistDescription!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<MusicProvider>(
              builder: (context, musicProvider, child) {
                final isCurrentPlaylist = musicProvider.currentPlaylistQueueItem?.id == playlistItem.id;
                return IconButton(
                  icon: Icon(
                    isCurrentPlaylist ? Icons.pause : Icons.play_arrow,
                  ),
                  onPressed: () async {
                    if (isCurrentPlaylist) {
                      await musicProvider.togglePlayPause();
                    } else {
                      await musicProvider.playPlaylistQueueItem(playlistItem);
                    }
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Remove from Queue'),
                    content: Text('Remove "${playlistItem.playlistName}" from the queue?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                
                if (confirmed == true) {
                  final queueProvider = context.read<QueueProvider>();
                  final success = await queueProvider.removePlaylistFromQueue(playlistItem.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success 
                            ? 'Removed from queue'
                            : 'Failed to remove from queue',
                        ),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
        onTap: () async {
          final musicProvider = context.read<MusicProvider>();
          await musicProvider.playPlaylistQueueItem(playlistItem);
        },
      ),
    );
  }

  Widget _buildTrackQueueItem(QueueItem queueItem, Track track, int index) {
    return Dismissible(
      key: Key(queueItem.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove from Queue'),
            content: Text('Remove "${track.title}" from the queue?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (direction) async {
        final queueProvider = context.read<QueueProvider>();
        final success = await queueProvider.removeFromQueue(queueItem.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success 
                  ? 'Removed from queue'
                  : 'Failed to remove from queue',
              ),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      },
      child: Consumer<MusicProvider>(
        builder: (context, musicProvider, child) {
          final isCurrentTrack = musicProvider.currentTrack?.id == track.id;
          final isPlaying = isCurrentTrack && musicProvider.isPlaying;
          final isLoading = isCurrentTrack && musicProvider.isLoading;
          
          return TrackTile(
            key: ValueKey(queueItem.id),
            track: track,
            isPlaying: isPlaying,
            isLoading: isLoading,
            showSaveButton: false,
            showQueueButton: false,
            onTap: () async {
              await musicProvider.playTrack(track);
            },
          );
        },
      ),
    );
  }
}
