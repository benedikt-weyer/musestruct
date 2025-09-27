import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../music/providers/music_provider.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/playlist_search_tile.dart';
import '../../widgets/copyable_error.dart';
import '../../widgets/service_filter.dart';
import '../../../music/models/music.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  String _lastQuery = '';
  SearchType _searchType = SearchType.tracks;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.trim().isNotEmpty && query != _lastQuery) {
      _lastQuery = query;
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      
      // Check if multi-service search is enabled but no services are selected
      if (musicProvider.useMultiServiceSearch && musicProvider.selectedServices.isEmpty) {
        // Don't perform search, let the UI show the warning
        return;
      }
      
      // Search both tracks and playlists simultaneously
      musicProvider.searchBoth(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Music'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Service filter and search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Service filter
                const ServiceFilter(),
                
                // Search type toggle
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    spacing: 16,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _searchType = SearchType.tracks;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _searchType == SearchType.tracks
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.music_note,
                                  color: _searchType == SearchType.tracks
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Tracks',
                                  style: TextStyle(
                                    color: _searchType == SearchType.tracks
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _searchType = SearchType.playlists;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _searchType == SearchType.playlists
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.queue_music,
                                  color: _searchType == SearchType.playlists
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Playlists',
                                  style: TextStyle(
                                    color: _searchType == SearchType.playlists
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _searchType == SearchType.tracks
                        ? 'Search for songs, artists, albums...'
                        : 'Search for playlists...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _lastQuery = '';
                              Provider.of<MusicProvider>(context, listen: false)
                                  .clearSearch();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: _performSearch,
                  onChanged: (value) {
                    setState(() {}); // Update UI to show/hide clear button
                  },
                ),
              ],
            ),
          ),
          
          // Search results
          Expanded(
            child: Consumer<MusicProvider>(
              builder: (context, musicProvider, child) {
                if (musicProvider.isSearching) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (musicProvider.searchError != null) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 24),
                          CopyableErrorWidget(
                            errorMessage: musicProvider.searchError!,
                            title: 'Search Error',
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () {
                              if (_searchController.text.isNotEmpty) {
                                _performSearch(_searchController.text);
                              }
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final searchResults = musicProvider.searchResults;
                
                if (searchResults == null) {
                  // Check if multi-service search is enabled but no services are selected
                  if (musicProvider.useMultiServiceSearch && musicProvider.selectedServices.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.filter_list_off,
                            size: 64,
                            color: Colors.orange[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Select Search Sources',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose at least one streaming service to search from',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Search for Music',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          musicProvider.useMultiServiceSearch
                              ? 'Discover and stream music from multiple sources'
                              : 'Discover and stream music from ${musicProvider.selectedService}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                // At this point, searchResults is guaranteed to be non-null

                // Check if we have results based on search type
                final hasResults = _searchType == SearchType.tracks 
                    ? (searchResults.tracks.isNotEmpty)
                    : (searchResults.playlists?.isNotEmpty ?? false);

                if (!hasResults) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Results Found',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try searching with different keywords',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_searchType == SearchType.tracks && searchResults.tracks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Tracks (${searchResults.tracks.length})',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: searchResults.tracks.length,
                          itemBuilder: (context, index) {
                            final track = searchResults.tracks[index];
                            return TrackTile(
                              track: track,
                              onTap: () {
                                musicProvider.playTrack(track);
                              },
                              showPlaylistButton: true,
                            );
                          },
                        ),
                      ),
                    ] else if (_searchType == SearchType.playlists && (searchResults.playlists?.isNotEmpty ?? false)) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Playlists (${searchResults.playlists?.length ?? 0})',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: searchResults.playlists?.length ?? 0,
                          itemBuilder: (context, index) {
                            try {
                              final playlist = searchResults.playlists![index];
                              return PlaylistSearchTile(
                                playlist: playlist,
                                onTap: () {
                                  // Playlists are not playable for now
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Playlists are not playable yet. Use the clone button to add them to your library.'),
                                      backgroundColor: Colors.orange,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              );
                            } catch (e) {
                              print('Error building playlist tile at index $index: $e');
                              return Container(
                                height: 80,
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.error),
                                    title: const Text('Error loading playlist'),
                                    subtitle: Text('Error: $e'),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
