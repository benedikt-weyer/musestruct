import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/models/music.dart';
import '../../music/providers/saved_albums_provider.dart';
import '../../music/providers/music_provider.dart';
import '../screens/playlists/select_playlist_for_album_dialog.dart';

class AlbumTile extends StatelessWidget {
  final Album album;
  final VoidCallback? onTap;
  final bool showCloneButton;
  final bool showRemoveButton;
  final VoidCallback? onRemove;

  const AlbumTile({
    super.key,
    required this.album,
    this.onTap,
    this.showCloneButton = false,
    this.showRemoveButton = false,
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
      default:
        return Colors.grey[600]!;
    }
  }

  String _getFormattedSource(String source) {
    switch (source.toLowerCase()) {
      case 'qobuz':
        return 'Qobuz';
      case 'spotify':
        return 'Spotify';
      case 'tidal':
        return 'Tidal';
      case 'apple_music':
        return 'Apple Music';
      case 'youtube_music':
        return 'YouTube Music';
      case 'deezer':
        return 'Deezer';
      default:
        return source.isNotEmpty ? source.toUpperCase() : 'Streaming';
    }
  }

  Widget _buildTrailing(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;
    final actions = <Widget>[];
    
    // Track count
    if (album.tracks.isNotEmpty) {
      actions.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            '${album.tracks.length} track${album.tracks.length != 1 ? 's' : ''}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
      );
    }
    
    if (isNarrowScreen) {
      // On narrow screens, show only menu button
      actions.add(_buildMenuButton(context));
    } else {
      // On larger screens, show action buttons plus menu
      if (showCloneButton) actions.add(_buildCloneButton(context));
      if (showRemoveButton) actions.add(_buildRemoveButton(context));
      actions.add(_buildMenuButton(context));
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions,
    );
  }

  Widget _buildMenuButton(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;
    final menuItems = <PopupMenuEntry<String>>[];
    
    // Always add view details and play options
    menuItems.add(
      PopupMenuItem<String>(
        value: 'view_details',
        child: Row(
          children: [
            Icon(
              Icons.info_outline, 
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            const Text('View Details'),
          ],
        ),
      ),
    );
    
    if (album.tracks.isNotEmpty) {
      menuItems.add(
        PopupMenuItem<String>(
          value: 'play_album',
          child: Row(
            children: [
              Icon(
                Icons.play_arrow, 
                size: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              const Text('Play Album'),
            ],
          ),
        ),
      );
      
      menuItems.add(
        PopupMenuItem<String>(
          value: 'add_to_playlist',
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
    
    // On narrow screens, include clone/remove in menu
    if (isNarrowScreen) {
      if (showCloneButton) {
        menuItems.add(const PopupMenuDivider());
        menuItems.add(
          PopupMenuItem<String>(
            value: 'clone',
            child: Consumer<SavedAlbumsProvider>(
              builder: (context, savedAlbumsProvider, child) {
                final isSaved = savedAlbumsProvider.isAlbumSaved(album.id, 
                    album.tracks.isNotEmpty ? album.tracks.first.source : 'streaming');
                return Row(
                  children: [
                    Icon(
                      isSaved ? Icons.library_add_check : Icons.library_add,
                      size: 20,
                      color: isSaved ? Colors.green : Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(isSaved ? 'Already in Library' : 'Clone to Library'),
                  ],
                );
              },
            ),
          ),
        );
      }
      
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

  Widget _buildCloneButton(BuildContext context) {
    return IconButton(
      icon: Consumer<SavedAlbumsProvider>(
        builder: (context, savedAlbumsProvider, child) {
          final isSaved = savedAlbumsProvider.isAlbumSaved(album.id, 
              album.tracks.isNotEmpty ? album.tracks.first.source : 'streaming');
          return Icon(
            isSaved ? Icons.library_add_check : Icons.library_add,
            color: isSaved ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          );
        },
      ),
      onPressed: () => _handleCloneAction(context),
      tooltip: 'Clone to library',
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 20,
    );
  }

  Widget _buildRemoveButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
      onPressed: onRemove,
      tooltip: 'Remove from library',
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 20,
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'view_details':
        // For now, show a snackbar. Later this could open an album details page
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Album details for "${album.title}" - ${album.tracks.length} tracks'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
          ),
        );
        break;
      case 'play_album':
        _handlePlayAlbumAction(context);
        break;
      case 'add_to_playlist':
        _handleAddToPlaylistAction(context);
        break;
      case 'clone':
        _handleCloneAction(context);
        break;
      case 'remove':
        if (onRemove != null) onRemove!();
        break;
    }
  }

  Future<void> _handleAddToPlaylistAction(BuildContext context) async {
    if (album.tracks.isNotEmpty) {
      // If tracks are already loaded, show the dialog directly
      showDialog(
        context: context,
        builder: (context) => SelectPlaylistForAlbumDialog(
          tracks: album.tracks,
          albumTitle: album.title,
        ),
      );
    } else {
      // If no tracks are loaded, we need to fetch them first
      // This case happens for albums from search results that don't have tracks loaded
      final savedAlbumsProvider = Provider.of<SavedAlbumsProvider>(context, listen: false);
      final source = album.source ?? 'qobuz'; // Default to qobuz if source is missing
      
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
        
        final tracks = await savedAlbumsProvider.getAlbumTracks(album.id, source);
        
        // Close loading dialog
        if (context.mounted) {
          Navigator.of(context).pop();
        }
        
        if (tracks != null && tracks.isNotEmpty && context.mounted) {
          showDialog(
            context: context,
            builder: (context) => SelectPlaylistForAlbumDialog(
              tracks: tracks,
              albumTitle: album.title,
            ),
          );
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No tracks found in this album'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
      } catch (e) {
        // Close loading dialog if still open
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load album tracks: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleCloneAction(BuildContext context) async {
    final savedAlbumsProvider = Provider.of<SavedAlbumsProvider>(context, listen: false);
    final source = album.tracks.isNotEmpty ? album.tracks.first.source : 'streaming';
    
    final isSaved = savedAlbumsProvider.isAlbumSaved(album.id, source);
    
    if (isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Album "${album.title}" is already in your library'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
        ),
      );
      return;
    }

    final success = await savedAlbumsProvider.saveAlbum(album);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success 
              ? 'Cloned "${album.title}" to your library'
              : 'Failed to clone album',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
        ),
      );
    }
  }

  Future<void> _handlePlayAlbumAction(BuildContext context) async {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    if (album.tracks.isEmpty) {
      // If no tracks are loaded, try to get them from the saved albums provider
      final savedAlbumsProvider = Provider.of<SavedAlbumsProvider>(context, listen: false);
      final source = album.tracks.isNotEmpty ? album.tracks.first.source : 'streaming';
      
      try {
        final tracks = await savedAlbumsProvider.getAlbumTracks(album.id, source);
        
        if (tracks != null && tracks.isNotEmpty && context.mounted) {
          // Play the first track and add the rest to queue
          await musicProvider.playTrack(tracks.first, clearQueue: true);
          
          // TODO: Add remaining tracks to queue once queue functionality is implemented
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Playing album "${album.title}" (${tracks.length} tracks)'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No tracks found in this album'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 100, left: 16, right: 16),
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
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
      }
    } else {
      // Play album tracks directly
      try {
        await musicProvider.playTrack(album.tracks.first, clearQueue: true);
        
        // TODO: Add remaining tracks to queue once queue functionality is implemented
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Playing album "${album.title}" (${album.tracks.length} tracks)'),
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
              content: Text('Failed to play album: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Extract source from the first track or use a default
    String source = 'streaming';
    if (album.tracks.isNotEmpty) {
      source = album.tracks.first.source;
    }

    return ListTile(
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[300],
        ),
        child: album.coverUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  album.coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.album,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    );
                  },
                ),
              )
            : Icon(
                Icons.album,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
      ),
      title: Text(
        album.title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            album.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (album.releaseDate != null) ...[
            const SizedBox(height: 2),
            Text(
              album.releaseDate!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
              ),
            ),
          ],
          const SizedBox(height: 4),
          // Source badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getSourceColor(source).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _getSourceColor(source).withOpacity(0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  _getFormattedSource(source),
                  style: TextStyle(
                    color: _getSourceColor(source),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
