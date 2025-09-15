import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/music_provider.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/backend_status_indicator.dart';
import '../../widgets/copyable_error.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  String _lastQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.trim().isNotEmpty && query != _lastQuery) {
      _lastQuery = query;
      Provider.of<MusicProvider>(context, listen: false).searchMusic(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Music'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: BackendStatusIndicator(compact: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Service selector and search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Service selector
                Consumer<MusicProvider>(
                  builder: (context, musicProvider, child) {
                    if (musicProvider.availableServices.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          const Text('Service: '),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButton<String>(
                              value: musicProvider.selectedService,
                              isExpanded: true,
                              items: musicProvider.availableServices.map((service) {
                                return DropdownMenuItem<String>(
                                  value: service.name,
                                  child: Row(
                                    children: [
                                      Icon(
                                        service.name == 'spotify' 
                                            ? Icons.music_note 
                                            : Icons.high_quality,
                                        size: 16,
                                        color: service.name == 'spotify' 
                                            ? Colors.green 
                                            : Colors.blue,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(service.displayName),
                                      if (!service.supportsFullTracks)
                                        Container(
                                          margin: const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Preview',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? value) {
                                if (value != null) {
                                  musicProvider.selectService(value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search for songs, artists, albums...',
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
                    filled: true,
                    fillColor: Colors.grey[100],
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
                          'Discover and stream music from Qobuz',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                if (searchResults.tracks.isEmpty) {
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
                    if (searchResults.tracks.isNotEmpty) ...[
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
                            );
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
