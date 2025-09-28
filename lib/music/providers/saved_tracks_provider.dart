import 'package:flutter/foundation.dart';
import '../models/music.dart';
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

  /// Update the BPM of a saved track
  void updateTrackBpm(String trackId, String source, double bpm) {
    bool updated = false;
    
    // Update saved tracks list
    for (int i = 0; i < _savedTracks.length; i++) {
      if (_savedTracks[i].trackId == trackId && _savedTracks[i].source == source) {
        _savedTracks[i] = SavedTrack(
          id: _savedTracks[i].id,
          trackId: _savedTracks[i].trackId,
          title: _savedTracks[i].title,
          artist: _savedTracks[i].artist,
          album: _savedTracks[i].album,
          duration: _savedTracks[i].duration,
          source: _savedTracks[i].source,
          coverUrl: _savedTracks[i].coverUrl,
          bpm: bpm,
          keyName: _savedTracks[i].keyName,
          camelot: _savedTracks[i].camelot,
          keyConfidence: _savedTracks[i].keyConfidence,
          createdAt: _savedTracks[i].createdAt,
        );
        updated = true;
        break;
      }
    }
    
    if (updated) {
      notifyListeners();
    }
  }

  /// Update the key of a saved track
  void updateTrackKey(String trackId, String source, String keyName, String camelot, double confidence) {
    bool updated = false;
    
    // Update saved tracks list
    for (int i = 0; i < _savedTracks.length; i++) {
      if (_savedTracks[i].trackId == trackId && _savedTracks[i].source == source) {
        _savedTracks[i] = SavedTrack(
          id: _savedTracks[i].id,
          trackId: _savedTracks[i].trackId,
          title: _savedTracks[i].title,
          artist: _savedTracks[i].artist,
          album: _savedTracks[i].album,
          duration: _savedTracks[i].duration,
          source: _savedTracks[i].source,
          coverUrl: _savedTracks[i].coverUrl,
          bpm: _savedTracks[i].bpm,
          keyName: keyName,
          camelot: camelot,
          keyConfidence: confidence,
          createdAt: _savedTracks[i].createdAt,
        );
        updated = true;
        break;
      }
    }
    
    if (updated) {
      notifyListeners();
    }
  }
}
