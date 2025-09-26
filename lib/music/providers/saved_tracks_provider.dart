import 'package:flutter/foundation.dart';
import '../../models/music.dart';
import '../services/saved_tracks_api_service.dart';

class SavedTracksProvider with ChangeNotifier {
  List<SavedTrack> _savedTracks = [];
  bool _isLoading = false;
  String? _error;
  Map<String, bool> _trackSavedStatus = {};

  List<SavedTrack> get savedTracks => _savedTracks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool isTrackSaved(String trackId, String source) {
    final key = '${trackId}_$source';
    return _trackSavedStatus[key] ?? false;
  }

  Future<void> loadSavedTracks({int page = 1, int limit = 50}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await SavedTracksApiService.getSavedTracks(page: page, limit: limit);
      
      if (response.success && response.data != null) {
        if (page == 1) {
          _savedTracks = response.data!;
        } else {
          _savedTracks.addAll(response.data!);
        }
        _updateTrackSavedStatus();
      } else {
        _error = response.message ?? 'Failed to load saved tracks';
      }
    } catch (e) {
      _error = 'Error loading saved tracks: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> saveTrack(Track track) async {
    try {
      final request = SaveTrackRequest.fromTrack(track);
      final response = await SavedTracksApiService.saveTrack(request);
      
      if (response.success && response.data != null) {
        _savedTracks.insert(0, response.data!);
        _trackSavedStatus['${track.id}_${track.source}'] = true;
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to save track';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error saving track: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeSavedTrack(String savedTrackId, String trackId, String source) async {
    try {
      final response = await SavedTracksApiService.removeSavedTrack(savedTrackId);
      
      if (response.success) {
        _savedTracks.removeWhere((track) => track.id == savedTrackId);
        _trackSavedStatus['${trackId}_$source'] = false;
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to remove saved track';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error removing saved track: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> checkTrackSavedStatus(String trackId, String source) async {
    try {
      final response = await SavedTracksApiService.isTrackSaved(trackId, source);
      
      if (response.success && response.data != null) {
        _trackSavedStatus['${trackId}_$source'] = response.data!;
        notifyListeners();
      }
    } catch (e) {
      // Silently fail for status checks
      if (kDebugMode) {
        print('Error checking track saved status: $e');
      }
    }
  }

  void _updateTrackSavedStatus() {
    for (final track in _savedTracks) {
      _trackSavedStatus['${track.trackId}_${track.source}'] = true;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void refresh() {
    loadSavedTracks();
  }
}
