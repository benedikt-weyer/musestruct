import 'package:flutter/foundation.dart';
import '../models/music.dart';
import '../services/saved_albums_api_service.dart';

class SavedAlbumsProvider with ChangeNotifier {
  List<SavedAlbum> _savedAlbums = [];
  bool _isLoading = false;
  String? _error;

  List<SavedAlbum> get savedAlbums => _savedAlbums;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load saved albums from the API
  Future<void> loadSavedAlbums() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await SavedAlbumsApiService.getSavedAlbums();
      if (response.success && response.data != null) {
        _savedAlbums = response.data!;
      } else {
        _error = response.message ?? 'Failed to load saved albums';
      }
    } catch (e) {
      _error = 'Error loading saved albums: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save an album to the collection
  Future<bool> saveAlbum(Album album) async {
    try {
      final request = SaveAlbumRequest.fromAlbum(album);
      final response = await SavedAlbumsApiService.saveAlbum(request);
      
      if (response.success && response.data != null) {
        // Add to the beginning of the list for better UX
        _savedAlbums.insert(0, response.data!);
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to save album';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error saving album: $e';
      notifyListeners();
      return false;
    }
  }

  /// Remove an album from the collection
  Future<bool> removeSavedAlbum(String savedAlbumId, String albumId, String source) async {
    try {
      final response = await SavedAlbumsApiService.removeSavedAlbum(savedAlbumId);
      
      if (response.success) {
        // Remove from the local list
        _savedAlbums.removeWhere((album) => album.id == savedAlbumId);
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to remove album';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error removing album: $e';
      notifyListeners();
      return false;
    }
  }

  /// Check if an album is saved
  bool isAlbumSaved(String albumId, String source) {
    return _savedAlbums.any((album) => 
        album.albumId == albumId && album.source == source);
  }

  /// Get saved album by album ID and source
  SavedAlbum? getSavedAlbum(String albumId, String source) {
    try {
      return _savedAlbums.firstWhere((album) => 
          album.albumId == albumId && album.source == source);
    } catch (e) {
      return null;
    }
  }

  /// Refresh the saved albums list
  Future<void> refresh() async {
    await loadSavedAlbums();
  }

  /// Clear any error messages
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get album tracks
  Future<List<Track>?> getAlbumTracks(String albumId, String source) async {
    try {
      final response = await SavedAlbumsApiService.getAlbumTracks(albumId, source);
      if (response.success && response.data != null) {
        return response.data!;
      } else {
        _error = response.message ?? 'Failed to load album tracks';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = 'Error loading album tracks: $e';
      notifyListeners();
      return null;
    }
  }
}
