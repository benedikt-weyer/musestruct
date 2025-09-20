import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/queue_provider.dart';
import '../../providers/music_provider.dart';
import '../../widgets/track_tile.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

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

          if (queueProvider.queue.isEmpty) {
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
                    'Add tracks to your queue to see them here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: queueProvider.queue.length,
            onReorder: (oldIndex, newIndex) async {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              
              final item = queueProvider.queue[oldIndex];
              final success = await queueProvider.reorderQueue(item.id, newIndex);
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success 
                        ? 'Queue reordered'
                        : 'Failed to reorder queue',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            itemBuilder: (context, index) {
              final queueItem = queueProvider.queue[index];
              final track = queueItem.toTrack();
              
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
            },
          );
        },
      ),
    );
  }
}
