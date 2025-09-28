import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/models/music.dart';
import '../../music/providers/saved_tracks_provider.dart';
import '../../music/providers/music_provider.dart';
import '../../queue/providers/queue_provider.dart';
import '../screens/playlists/select_playlist_dialog.dart';
import 'network_image_widget.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool isPlaying;
  final bool isLoading;
  final bool showSaveButton;
  final bool showQueueButton;
  final bool showPlaylistButton;
  final bool showRemoveButton;
  final bool showTrackNumber;
  final int? trackNumber;
  final VoidCallback? onRemove;

  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.isPlaying = false,
    this.isLoading = false,
    this.showSaveButton = true,
    this.showQueueButton = true,
    this.showPlaylistButton = false,
    this.showRemoveButton = false,
    this.showTrackNumber = false,
    this.trackNumber,
    this.onRemove,
  });

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'qobuz':
        return const Color(0xFF00D4AA); // Qobuz green
      case 'spotify':
        return const Color(0xFF1DB954); // Spotify green
      case 'tidal':
        return const Color(0xFF000000); // Tidal black
      case 'apple_music':
        return const Color(0xFFFA243C); // Apple Music red
      case 'youtube_music':
        return const Color(0xFFFF0000); // YouTube red
      case 'deezer':
        return const Color(0xFF00C7B7); // Deezer cyan
      case 'server':
        return const Color(0xFF6B46C1); // Purple for server/local files
      default:
        return Colors.grey[600]!;
    }
  }

  Widget _buildTrailing(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600; // Use 600dp as breakpoint for phones vs tablets
    
    final actions = <Widget>[];
    
    // Duration text (if available)
    if (track.duration != null) {
      actions.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            track.formattedDuration,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
      );
    }
    
    // Quality badge (if available)
    if (track.quality != null) {
      actions.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              track.quality!.toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
    
    if (isNarrowScreen) {
      // On narrow screens, show only duration/quality and a menu button
      actions.add(_buildMenuButton(context));
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: actions,
      );
    } else {
      // On larger screens, show all action buttons plus menu for play options
      if (showQueueButton) actions.add(_buildQueueButton(context));
      if (showSaveButton) actions.add(_buildSaveButton(context));
      if (showPlaylistButton) actions.add(_buildPlaylistButton(context));
      if (showRemoveButton) actions.add(_buildRemoveButton(context));
      
      // Always add menu button for play options
      actions.add(_buildMenuButton(context));
      
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: actions,
      );
    }
  }

  Widget _buildMenuButton(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;
    final menuItems = <PopupMenuEntry<String>>[];
    
    // Always add play options
    menuItems.add(
      PopupMenuItem<String>(
        value: 'play_clear_queue',
        child: Row(
          children: [
            Icon(
              Icons.play_arrow, 
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            const Text('Play Now (Clear Queue)'),
          ],
        ),
      ),
    );
    
    menuItems.add(
      PopupMenuItem<String>(
        value: 'play_keep_queue',
        child: Row(
          children: [
            Icon(
              Icons.play_arrow, 
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            const Text('Play Now (Keep Queue)'),
          ],
        ),
      ),
    );
    
    // On narrow screens, include all options in menu
    // On larger screens, only include options that don't have dedicated buttons
    if (isNarrowScreen) {
      if (showQueueButton) {
        menuItems.add(const PopupMenuDivider());
        menuItems.add(
          PopupMenuItem<String>(
            value: 'queue',
            child: Row(
              children: [
                Icon(
                  Icons.queue_music, 
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                const Text('Add to Queue'),
              ],
            ),
          ),
        );
      }
    } else {
      // On larger screens, queue button is separate, so don't duplicate it in menu
      // Only show queue option if the button is not shown
      if (showQueueButton == false) {
        menuItems.add(const PopupMenuDivider());
        menuItems.add(
          PopupMenuItem<String>(
            value: 'queue',
            child: Row(
              children: [
                Icon(
                  Icons.queue_music, 
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                const Text('Add to Queue'),
              ],
            ),
          ),
        );
      }
    }
    
    // Handle save button - add to menu on narrow screens only (on larger screens it has its own button)
    if (showSaveButton && isNarrowScreen) {
      if (menuItems.isNotEmpty) menuItems.add(const PopupMenuDivider());
      menuItems.add(
        PopupMenuItem<String>(
          value: 'save',
          child: Consumer<SavedTracksProvider>(
            builder: (context, savedTracksProvider, child) {
              final isSaved = savedTracksProvider.isTrackSaved(track.id, track.source);
              return Row(
                children: [
                  Icon(
                    isSaved ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: isSaved ? Colors.red : Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(isSaved ? 'Remove from Saved' : 'Save Track'),
                ],
              );
            },
          ),
        ),
      );
    }
    
    // Handle playlist button - add to menu on narrow screens only (on larger screens it has its own button)
    if (showPlaylistButton && isNarrowScreen) {
      if (menuItems.isNotEmpty) menuItems.add(const PopupMenuDivider());
      menuItems.add(
        PopupMenuItem<String>(
          value: 'playlist',
          child: Row(
            children: [
              Icon(
                Icons.playlist_add, 
                size: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              const Text('Add to Playlist'),
            ],
          ),
        ),
      );
    }
    
    // Handle remove button - always in menu when shown
    if (showRemoveButton) {
      if (menuItems.isNotEmpty) menuItems.add(const PopupMenuDivider());
      menuItems.add(
        const PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Remove', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      );
    }
    
    if (menuItems.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (context) => menuItems,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 20,
      tooltip: 'More actions',
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'play_clear_queue':
        _handlePlayAction(context, clearQueue: true);
        break;
      case 'play_keep_queue':
        _handlePlayAction(context, clearQueue: false);
        break;
      case 'queue':
        _handleQueueAction(context);
        break;
      case 'save':
        _handleSaveAction(context);
        break;
      case 'playlist':
        _handlePlaylistAction(context);
        break;
      case 'remove':
        if (onRemove != null) onRemove!();
        break;
    }
  }

  Widget _buildQueueButton(BuildContext context) {
    return IconButton(
      icon: Consumer<QueueProvider>(
        builder: (context, queueProvider, child) {
          return queueProvider.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.queue_music, size: 20);
        },
      ),
      onPressed: () => _handleQueueAction(context),
      tooltip: 'Add to queue',
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 20,
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    return IconButton(
      icon: Consumer<SavedTracksProvider>(
        builder: (context, savedTracksProvider, child) {
          final isSaved = savedTracksProvider.isTrackSaved(track.id, track.source);
          return Icon(
            isSaved ? Icons.favorite : Icons.favorite_border,
            color: isSaved ? Colors.red : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          );
        },
      ),
      onPressed: () => _handleSaveAction(context),
      tooltip: 'Toggle saved track',
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 20,
    );
  }

  Widget _buildPlaylistButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.playlist_add, size: 20),
      onPressed: () => _handlePlaylistAction(context),
      tooltip: 'Add to playlist',
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 20,
    );
  }

  Widget _buildRemoveButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
      onPressed: onRemove,
      tooltip: 'Remove from playlist',
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 20,
    );
  }

  Future<void> _handlePlayAction(BuildContext context, {required bool clearQueue}) async {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    try {
      await musicProvider.playTrack(track, clearQueue: clearQueue);
      
      if (context.mounted) {
        final message = clearQueue 
            ? 'Playing "${track.title}"'
            : 'Playing "${track.title}" (queue kept)';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
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
  }

  Future<void> _handleQueueAction(BuildContext context) async {
    final queueProvider = Provider.of<QueueProvider>(context, listen: false);
    if (queueProvider.isLoading) return;
    
    final success = await queueProvider.addToQueue(track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success 
              ? 'Added "${track.title}" to queue'
              : 'Failed to add track to queue',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
        ),
      );
    }
  }

  Future<void> _handleSaveAction(BuildContext context) async {
    final savedTracksProvider = Provider.of<SavedTracksProvider>(context, listen: false);
    final isSaved = savedTracksProvider.isTrackSaved(track.id, track.source);
    
    if (isSaved) {
      // Find the saved track to remove
      final savedTrack = savedTracksProvider.savedTracks
          .where((st) => st.trackId == track.id && st.source == track.source)
          .firstOrNull;
      if (savedTrack != null) {
        await savedTracksProvider.removeSavedTrack(
          savedTrack.id,
          track.id,
          track.source,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Removed "${track.title}" from saved tracks'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
      }
    } else {
      final success = await savedTracksProvider.saveTrack(track);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success 
                ? 'Added "${track.title}" to saved tracks'
                : 'Failed to save track',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
          ),
        );
      }
    }
  }

  void _handlePlaylistAction(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SelectPlaylistDialog(track: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: showTrackNumber && trackNumber != null
          ? Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Center(
                child: Text(
                  trackNumber.toString(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[300],
                  ),
                  child: NetworkImageWidget(
                    imageUrl: track.coverUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(8),
                    errorWidget: Icon(
                      Icons.music_note,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (isLoading)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black54,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (isPlaying && !isLoading && !showTrackNumber)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black54,
                    ),
                    child: const Icon(
                      Icons.volume_up,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
      title: Text(
        track.title,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
          color: isPlaying ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying 
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.7)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            track.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
          // Source and quality info
          Row(
            children: [
              // Source badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getSourceColor(track.source).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _getSourceColor(track.source).withOpacity(0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  track.formattedSource,
                  style: TextStyle(
                    color: _getSourceColor(track.source),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Audio quality info
              if (track.formattedQuality.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  track.formattedQuality,
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // BPM info
              if (track.bpm != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${track.bpm!.toStringAsFixed(0)} BPM',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              // Key info
              if (track.keyName != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${track.keyName!} / ${track.camelot ?? ''}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: _buildTrailing(context),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
