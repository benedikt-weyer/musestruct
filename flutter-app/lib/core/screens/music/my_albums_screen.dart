import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../music/providers/saved_albums_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/album_tile.dart';

class MyAlbumsScreen extends StatefulWidget {
  const MyAlbumsScreen({super.key});

  @override
  State<MyAlbumsScreen> createState() => _MyAlbumsScreenState();
}

class _MyAlbumsScreenState extends State<MyAlbumsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SavedAlbumsProvider>().loadSavedAlbums();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Albums'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<SavedAlbumsProvider>().refresh();
            },
          ),
        ],
      ),
      body: Consumer<SavedAlbumsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.savedAlbums.isEmpty) {
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
                    'Error loading saved albums',
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

          if (provider.savedAlbums.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.album,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved albums yet',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Clone albums from search results to see them here',
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
              await provider.loadSavedAlbums();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.savedAlbums.length,
              itemBuilder: (context, index) {
                final savedAlbum = provider.savedAlbums[index];
                final album = savedAlbum.toAlbum();
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: AlbumTile(
                    album: album,
                    showRemoveButton: true,
                    onTap: () {
                      // Navigate to album detail screen using navigation provider
                      final navigationProvider = Provider.of<NavigationProvider>(context, listen: false);
                      navigationProvider.navigateToAlbumDetail(savedAlbum.albumId, savedAlbum);
                    },
                    onRemove: () async {
                      final success = await provider.removeSavedAlbum(
                        savedAlbum.id,
                        savedAlbum.albumId,
                        savedAlbum.source,
                      );
                      
                      if (success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Removed "${savedAlbum.title}" from library'),
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
