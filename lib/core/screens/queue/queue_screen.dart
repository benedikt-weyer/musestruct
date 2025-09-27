import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../queue/providers/queue_provider.dart';
import '../../../music/providers/music_provider.dart';
import '../../../music/models/music.dart';
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
                                behavior: SnackBarBehavior.floating,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Now Playing',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
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
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          child: Icon(
            Icons.queue_music,
            color: Theme.of(context).colorScheme.primary,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            if (playlistItem.playlistDescription != null && playlistItem.playlistDescription!.isNotEmpty)
              Text(
                playlistItem.playlistDescription!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Loop mode control
            PopupMenuButton<LoopMode>(
              icon: Icon(
                _getLoopModeIcon(playlistItem.loopMode),
                color: Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: 'Change repeat mode',
              onSelected: (LoopMode newLoopMode) async {
                final queueProvider = context.read<QueueProvider>();
                final updatedItem = playlistItem.copyWith(loopMode: newLoopMode);
                final success = await queueProvider.updatePlaylistQueueItem(updatedItem);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success 
                          ? 'Repeat mode changed to ${_getLoopModeText(newLoopMode)}'
                          : 'Failed to change repeat mode',
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<LoopMode>(
                  value: LoopMode.once,
                  child: Row(
                    children: [
                      Icon(
                        _getLoopModeIcon(LoopMode.once),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Text(_getLoopModeText(LoopMode.once)),
                    ],
                  ),
                ),
                PopupMenuItem<LoopMode>(
                  value: LoopMode.twice,
                  child: Row(
                    children: [
                      Icon(
                        _getLoopModeIcon(LoopMode.twice),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Text(_getLoopModeText(LoopMode.twice)),
                    ],
                  ),
                ),
                PopupMenuItem<LoopMode>(
                  value: LoopMode.infinite,
                  child: Row(
                    children: [
                      Icon(
                        _getLoopModeIcon(LoopMode.infinite),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Text(_getLoopModeText(LoopMode.infinite)),
                    ],
                  ),
                ),
              ],
            ),
            // Play mode control
            PopupMenuButton<PlayMode>(
              icon: Icon(
                _getPlayModeIcon(playlistItem.playMode),
                color: Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: 'Change playback order',
              onSelected: (PlayMode newPlayMode) async {
                final queueProvider = context.read<QueueProvider>();
                final updatedItem = playlistItem.copyWith(playMode: newPlayMode);
                final success = await queueProvider.updatePlaylistQueueItem(updatedItem);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success 
                          ? 'Playback order changed to ${_getPlayModeText(newPlayMode)}'
                          : 'Failed to change playback order',
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<PlayMode>(
                  value: PlayMode.normal,
                  child: Row(
                    children: [
                      Icon(
                        _getPlayModeIcon(PlayMode.normal),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Text(_getPlayModeText(PlayMode.normal)),
                    ],
                  ),
                ),
                PopupMenuItem<PlayMode>(
                  value: PlayMode.shuffle,
                  child: Row(
                    children: [
                      Icon(
                        _getPlayModeIcon(PlayMode.shuffle),
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Text(_getPlayModeText(PlayMode.shuffle)),
                    ],
                  ),
                ),
              ],
            ),
            Consumer<MusicProvider>(
              builder: (context, musicProvider, child) {
                final isCurrentPlaylist = musicProvider.currentPlaylistQueueItem?.id == playlistItem.id;
                return IconButton(
                  icon: Icon(
                    isCurrentPlaylist ? Icons.pause : Icons.play_arrow,
                    color: Theme.of(context).colorScheme.onSurface,
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
                        behavior: SnackBarBehavior.floating,
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
              behavior: SnackBarBehavior.floating,
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

  // Helper methods for loop mode
  IconData _getLoopModeIcon(LoopMode loopMode) {
    switch (loopMode) {
      case LoopMode.once:
        return Icons.repeat;
      case LoopMode.twice:
        return Icons.repeat_one;
      case LoopMode.infinite:
        return Icons.repeat;
    }
  }

  String _getLoopModeText(LoopMode loopMode) {
    switch (loopMode) {
      case LoopMode.once:
        return 'Play Once';
      case LoopMode.twice:
        return 'Play Twice';
      case LoopMode.infinite:
        return 'Repeat Forever';
    }
  }

  // Helper methods for play mode
  IconData _getPlayModeIcon(PlayMode playMode) {
    switch (playMode) {
      case PlayMode.normal:
        return Icons.queue_music;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  String _getPlayModeText(PlayMode playMode) {
    switch (playMode) {
      case PlayMode.normal:
        return 'Normal Order';
      case PlayMode.shuffle:
        return 'Shuffle';
    }
  }
}
