import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';

class PlaylistProvider with ChangeNotifier {
  List<Playlist> _playlists = [];
  List<PlaylistItem> _currentPlaylistItems = [];
  Playlist? _currentPlaylist;
  bool _isLoading = false;
  String? _error;
  String? _searchQuery;

  // Getters
  List<Playlist> get playlists => _playlists;
  List<PlaylistItem> get currentPlaylistItems => _currentPlaylistItems;
  Playlist? get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get searchQuery => _searchQuery;

  // Initialize playlists
  Future<void> initialize() async {
    await loadPlaylists();
  }

  // Load all playlists
  Future<void> loadPlaylists({String? search}) async {
    try {
      _isLoading = true;
      _error = null;
      _searchQuery = search;
      notifyListeners();

      final response = await PlaylistApiService.getPlaylists(
        search: search,
        perPage: 100, // Load more playlists
      );

      print('PlaylistProvider: Load playlists response success: ${response.success}');
      print('PlaylistProvider: Load playlists response message: ${response.message}');
      print('PlaylistProvider: Load playlists response data: ${response.data}');

      if (response.success && response.data != null) {
        _playlists = response.data!.playlists;
        print('PlaylistProvider: Loaded ${_playlists.length} playlists');
      } else {
        _error = response.message ?? 'Failed to load playlists';
        print('PlaylistProvider: Error loading playlists: $_error');
      }
    } catch (e) {
      _error = 'Failed to load playlists: $e';
      print('PlaylistProvider: Exception loading playlists: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a new playlist
  Future<bool> createPlaylist({
    required String name,
    String? description,
    bool isPublic = false,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final request = CreatePlaylistRequest(
        name: name,
        description: description,
        isPublic: isPublic,
      );

      final response = await PlaylistApiService.createPlaylist(request);

      if (response.success && response.data != null) {
        _playlists.insert(0, response.data!);
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to create playlist';
        return false;
      }
    } catch (e) {
      _error = 'Failed to create playlist: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update a playlist
  Future<bool> updatePlaylist({
    required String playlistId,
    String? name,
    String? description,
    bool? isPublic,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final request = UpdatePlaylistRequest(
        name: name,
        description: description,
        isPublic: isPublic,
      );

      final response = await PlaylistApiService.updatePlaylist(playlistId, request);

      if (response.success && response.data != null) {
        final index = _playlists.indexWhere((p) => p.id == playlistId);
        if (index != -1) {
          _playlists[index] = response.data!;
        }
        if (_currentPlaylist?.id == playlistId) {
          _currentPlaylist = response.data!;
        }
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to update playlist';
        return false;
      }
    } catch (e) {
      _error = 'Failed to update playlist: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a playlist
  Future<bool> deletePlaylist(String playlistId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await PlaylistApiService.deletePlaylist(playlistId);

      if (response.success) {
        _playlists.removeWhere((p) => p.id == playlistId);
        if (_currentPlaylist?.id == playlistId) {
          _currentPlaylist = null;
          _currentPlaylistItems = [];
        }
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to delete playlist';
        return false;
      }
    } catch (e) {
      _error = 'Failed to delete playlist: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load playlist items
  Future<void> loadPlaylistItems(String playlistId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await PlaylistApiService.getPlaylistItems(playlistId);

      if (response.success && response.data != null) {
        _currentPlaylistItems = response.data!;
        // Also load the playlist details
        await _loadPlaylistDetails(playlistId);
      } else {
        _error = response.message ?? 'Failed to load playlist items';
      }
    } catch (e) {
      _error = 'Failed to load playlist items: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load playlist details
  Future<void> _loadPlaylistDetails(String playlistId) async {
    try {
      final response = await PlaylistApiService.getPlaylist(playlistId);
      if (response.success && response.data != null) {
        _currentPlaylist = response.data!;
      }
    } catch (e) {
      // Ignore errors for playlist details
    }
  }

  // Add item to playlist
  Future<bool> addItemToPlaylist({
    required String playlistId,
    required String itemType, // "track" or "playlist"
    required String itemId,
    int? position,
    // Track details (only used when itemType is "track")
    String? title,
    String? artist,
    String? album,
    int? duration,
    String? source,
    String? coverUrl,
    // Playlist details (only used when itemType is "playlist")
    String? playlistName,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final request = AddPlaylistItemRequest(
        itemType: itemType,
        itemId: itemId,
        position: position,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        source: source,
        coverUrl: coverUrl,
        playlistName: playlistName,
      );

      final response = await PlaylistApiService.addPlaylistItem(playlistId, request);

      if (response.success && response.data != null) {
        // Reload playlist items to get updated list
        await loadPlaylistItems(playlistId);
        return true;
      } else {
        _error = response.message ?? 'Failed to add item to playlist';
        return false;
      }
    } catch (e) {
      _error = 'Failed to add item to playlist: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Convenience method for adding tracks
  Future<bool> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
    required String title,
    required String artist,
    required String album,
    int? duration,
    String? source,
    String? coverUrl,
    int? position,
  }) async {
    return addItemToPlaylist(
      playlistId: playlistId,
      itemType: 'track',
      itemId: trackId,
      position: position,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      source: source,
      coverUrl: coverUrl,
    );
  }

  // Remove item from playlist
  Future<bool> removeItemFromPlaylist(String playlistId, String itemId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await PlaylistApiService.removePlaylistItem(playlistId, itemId);

      if (response.success) {
        // Reload playlist items to get updated list
        await loadPlaylistItems(playlistId);
        return true;
      } else {
        _error = response.message ?? 'Failed to remove item from playlist';
        return false;
      }
    } catch (e) {
      _error = 'Failed to remove item from playlist: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Reorder playlist item
  Future<bool> reorderPlaylistItem({
    required String playlistId,
    required String itemId,
    required int newPosition,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final request = ReorderPlaylistItemRequest(newPosition: newPosition);
      final response = await PlaylistApiService.reorderPlaylistItem(
        playlistId,
        itemId,
        request,
      );

      if (response.success) {
        // Reload playlist items to get updated list
        await loadPlaylistItems(playlistId);
        return true;
      } else {
        _error = response.message ?? 'Failed to reorder playlist item';
        return false;
      }
    } catch (e) {
      _error = 'Failed to reorder playlist item: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Clear current playlist
  void clearCurrentPlaylist() {
    _currentPlaylist = null;
    _currentPlaylistItems = [];
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Search playlists
  Future<void> searchPlaylists(String query) async {
    await loadPlaylists(search: query);
  }

  // Clear search
  Future<void> clearSearch() async {
    await loadPlaylists();
  }
}
