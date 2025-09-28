import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../music/providers/music_provider.dart';
import '../../../music/providers/saved_albums_provider.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/album_tile.dart';
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
  bool _isLibrarySearch = false; // New field for library search toggle

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
      
      // Search tracks, albums, and playlists simultaneously
      if (_isLibrarySearch) {
        musicProvider.searchLibrary(query, searchType: _searchType);
      } else {
        musicProvider.searchBoth(query);
      }
    }
  }

  bool _shouldShowSearchAllButton(MusicProvider musicProvider) {
    // Show Search All button when library search is active OR when server is the selected source
    if (_isLibrarySearch) {
      return true;
    }
    
    if (musicProvider.useMultiServiceSearch) {
      // In multi-service mode, show if only server is selected
      return musicProvider.selectedServices.length == 1 && 
             musicProvider.selectedServices.contains('server');
    } else {
      // In single service mode, show if server is selected
      return musicProvider.selectedService == 'server';
    }
  }

  void _performSearchAll() {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    // Clear the search input
    _searchController.clear();
    _lastQuery = '';
    
    // Perform search with empty query to get all results
    if (_isLibrarySearch) {
      musicProvider.searchAllLibrary(searchType: _searchType);
    } else {
      musicProvider.searchAll();
    }
  }

  List<int> _getVisiblePageNumbers(int currentPage, int totalPages) {
    const int maxVisible = 7; // Maximum number of page buttons to show
    
    if (totalPages <= maxVisible) {
      return List.generate(totalPages, (index) => index + 1);
    }
    
    List<int> pages = [];
    
    // Always show first page
    pages.add(1);
    
    // Calculate range around current page
    int start = (currentPage - 2).clamp(2, totalPages - 1);
    int end = (currentPage + 2).clamp(2, totalPages - 1);
    
    // Add ellipsis if needed before range
    if (start > 2) {
      pages.add(-1); // -1 represents ellipsis
    }
    
    // Add pages around current page
    for (int i = start; i <= end; i++) {
      if (i != 1 && i != totalPages) {
        pages.add(i);
      }
    }
    
    // Add ellipsis if needed after range
    if (end < totalPages - 1) {
      pages.add(-1); // -1 represents ellipsis
    }
    
    // Always show last page
    if (totalPages > 1) {
      pages.add(totalPages);
    }
    
    return pages;
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
                
                // Library search toggle (only show when not "Server" is selected)
                Consumer<MusicProvider>(
                  builder: (context, musicProvider, child) {
                    // Only show library toggle when streaming services (not server) are selected
                    bool showLibraryToggle = false;
                    if (musicProvider.useMultiServiceSearch) {
                      showLibraryToggle = musicProvider.selectedServices.any((service) => service != 'server');
                    } else {
                      showLibraryToggle = musicProvider.selectedService != 'server';
                    }
                    
                    if (!showLibraryToggle) {
                      return const SizedBox.shrink();
                    }
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isLibrarySearch = false;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: !_isLibrarySearch
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    bottomLeft: Radius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'All',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: !_isLibrarySearch
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isLibrarySearch = true;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _isLibrarySearch
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'My Library',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _isLibrarySearch
                                        ? Colors.white
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
                // Search type toggle
                Consumer<MusicProvider>(
                  builder: (context, musicProvider, child) {
                    // Server now supports playlists, so no need to hide playlist functionality
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        spacing: 8,
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
                                    const SizedBox(width: 4),
                                    Text(
                                      'Tracks',
                                      style: TextStyle(
                                        color: _searchType == SearchType.tracks
                                            ? Colors.white
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
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
                                  _searchType = SearchType.albums;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _searchType == SearchType.albums
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.album,
                                      color: _searchType == SearchType.albums
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Albums',
                                      style: TextStyle(
                                        color: _searchType == SearchType.albums
                                            ? Colors.white
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
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
                                      const SizedBox(width: 4),
                                      Text(
                                        'Playlists',
                                        style: TextStyle(
                                          color: _searchType == SearchType.playlists
                                              ? Colors.white
                                              : Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                
                // Search bar with optional Search All button
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: _searchType == SearchType.tracks
                              ? 'Search for songs, artists...'
                              : _searchType == SearchType.albums
                              ? 'Search for albums...'
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
                    ),
                    // Show Search All button only when server is selected as source
                    Consumer<MusicProvider>(
                      builder: (context, musicProvider, child) {
                        final showSearchAllButton = _shouldShowSearchAllButton(musicProvider);
                        
                        if (!showSearchAllButton) {
                          return const SizedBox.shrink();
                        }
                        
                        return Container(
                          margin: const EdgeInsets.only(left: 8),
                          child: ElevatedButton.icon(
                            onPressed: () => _performSearchAll(),
                            icon: const Icon(Icons.library_music, size: 18),
                            label: const Text('Search All'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
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
                    : _searchType == SearchType.albums
                    ? (searchResults.albums.isNotEmpty)
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
                    // Pagination info
                    if (musicProvider.totalPages > 1) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          children: [
                            Text(
                              'Page ${musicProvider.currentPage} of ${musicProvider.totalPages}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${searchResults.total} total results',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    if (_searchType == SearchType.tracks && searchResults.tracks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Tracks (${searchResults.tracks.length}${musicProvider.totalPages > 1 ? ' on this page' : ''})',
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
                                musicProvider.playTrack(track); // Default clears queue
                              },
                              showPlaylistButton: true,
                            );
                          },
                        ),
                      ),
                    ] else if (_searchType == SearchType.albums && searchResults.albums.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Albums (${searchResults.albums.length}${musicProvider.totalPages > 1 ? ' on this page' : ''})',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: searchResults.albums.length,
                          itemBuilder: (context, index) {
                            final album = searchResults.albums[index];
                            return AlbumTile(
                              album: album,
                              showCloneButton: true,
                              onTap: () async {
                                // Play the album
                                final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                                final savedAlbumsProvider = Provider.of<SavedAlbumsProvider>(context, listen: false);
                                
                                if (album.tracks.isNotEmpty) {
                                  try {
                                    await musicProvider.playTrack(album.tracks.first, clearQueue: true);
                                    
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
                                } else {
                                  // If no tracks are loaded, try to get them from the source
                                  final source = album.source ?? 'qobuz'; // Default to qobuz if source is missing
                                  
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
                                          content: Text('Failed to load album tracks: $e'),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ] else if (_searchType == SearchType.playlists && (searchResults.playlists?.isNotEmpty ?? false)) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Playlists (${searchResults.playlists?.length ?? 0}${musicProvider.totalPages > 1 ? ' on this page' : ''})',
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
                    
                    // Pagination controls
                    if (musicProvider.totalPages > 1 || searchResults.total > musicProvider.itemsPerPage) ...[
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // Page size selector
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Results per page:',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                DropdownButton<int>(
                                  value: musicProvider.itemsPerPage,
                                  items: musicProvider.availablePageSizes.map((size) {
                                    return DropdownMenuItem<int>(
                                      value: size,
                                      child: Text('$size'),
                                    );
                                  }).toList(),
                                  onChanged: (newSize) {
                                    if (newSize != null) {
                                      musicProvider.changePageSize(newSize);
                                    }
                                  },
                                  underline: Container(),
                                  isDense: true,
                                ),
                              ],
                            ),
                            
                            if (musicProvider.totalPages > 1) ...[
                              const SizedBox(height: 16),
                              // Navigation controls
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Previous button
                                  IconButton(
                                    onPressed: musicProvider.hasPreviousPage 
                                        ? () => musicProvider.previousPage()
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                    tooltip: 'Previous page',
                                  ),
                                  
                                  // Page numbers
                                  ...List.generate(
                                    _getVisiblePageNumbers(musicProvider.currentPage, musicProvider.totalPages).length,
                                    (index) {
                                      final pageNumber = _getVisiblePageNumbers(musicProvider.currentPage, musicProvider.totalPages)[index];
                                      final isCurrentPage = pageNumber == musicProvider.currentPage;
                                      
                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        child: pageNumber == -1
                                            ? const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8),
                                                child: Text('...'),
                                              )
                                            : TextButton(
                                                onPressed: isCurrentPage 
                                                    ? null 
                                                    : () => musicProvider.goToPage(pageNumber),
                                                style: TextButton.styleFrom(
                                                  backgroundColor: isCurrentPage 
                                                      ? Theme.of(context).primaryColor 
                                                      : null,
                                                  foregroundColor: isCurrentPage 
                                                      ? Colors.white 
                                                      : null,
                                                  minimumSize: const Size(40, 40),
                                                ),
                                                child: Text('$pageNumber'),
                                              ),
                                      );
                                    },
                                  ),
                                  
                                  // Next button
                                  IconButton(
                                    onPressed: musicProvider.hasNextPage 
                                        ? () => musicProvider.nextPage()
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                    tooltip: 'Next page',
                                  ),
                                ],
                              ),
                            ],
                          ],
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
