import 'dart:convert';
import '../services/api_service.dart';
import '../services/base_api_service.dart';
import '../../music/models/music.dart';

class AudioAnalysisService {
  final ApiService _apiService;

  AudioAnalysisService(this._apiService);

  /// Analyze BPM of a track using spectrogram approach
  Future<SpectrogramBpmAnalysisResult> analyzeBpmSpectrogram(Track track) async {
    try {
      final response = await _apiService.post(
        '/audio/analyze-bpm-spectrogram',
        queryParameters: {
          'track_id': track.id,
          'source': track.source,
          if (track.streamUrl != null) 'stream_url': track.streamUrl!,
        },
        timeout: BaseApiService.analysisTimeout, // Use longer timeout for analysis
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return SpectrogramBpmAnalysisResult.fromJson(data['data']);
        } else {
          throw Exception(data['message'] ?? 'Spectrogram BPM analysis failed');
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Spectrogram BPM analysis request failed');
      }
    } catch (e) {
      throw Exception('Failed to analyze BPM with spectrogram: $e');
    }
  }

  /// Analyze BPM of a track (legacy windowed approach)
  Future<BpmAnalysisResult> analyzeBpm(Track track) async {
    try {
      final response = await _apiService.post(
        '/audio/analyze-bpm',
        queryParameters: {
          'track_id': track.id,
          'source': track.source,
          if (track.streamUrl != null) 'stream_url': track.streamUrl!,
        },
        timeout: BaseApiService.analysisTimeout, // Use longer timeout for analysis
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return BpmAnalysisResult.fromJson(data['data']);
        } else {
          throw Exception(data['message'] ?? 'BPM analysis failed');
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'BPM analysis request failed');
      }
    } catch (e) {
      throw Exception('Failed to analyze BPM: $e');
    }
  }

  /// Analyze key of a track
  Future<KeyAnalysisResult> analyzeKey(Track track) async {
    try {
      final response = await _apiService.post(
        '/audio/analyze-key',
        queryParameters: {
          'track_id': track.id,
          'source': track.source,
          if (track.streamUrl != null) 'stream_url': track.streamUrl!,
        },
        timeout: BaseApiService.analysisTimeout, // Use longer timeout for analysis
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return KeyAnalysisResult.fromJson(data['data']);
        } else {
          throw Exception(data['message'] ?? 'Key analysis failed');
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Key analysis request failed');
      }
    } catch (e) {
      throw Exception('Failed to analyze key: $e');
    }
  }

  /// Get BPM for a track if it has been analyzed
  Future<double?> getBpm(Track track) async {
    try {
      final response = await _apiService.get(
        '/audio/bpm',
        queryParameters: {
          'track_id': track.id,
          'source': track.source,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final bpmData = BpmResponse.fromJson(data['data']);
          return bpmData.bpm;
        }
      }
      return null;
    } catch (e) {
      print('Failed to get BPM: $e');
      return null;
    }
  }
}

class KeyAnalysisResult {
  final String trackId;
  final String source;
  final String keyName;
  final String camelot;
  final double confidence;
  final bool isMajor;
  final int analysisTimeMs;

  KeyAnalysisResult({
    required this.trackId,
    required this.source,
    required this.keyName,
    required this.camelot,
    required this.confidence,
    required this.isMajor,
    required this.analysisTimeMs,
  });

  factory KeyAnalysisResult.fromJson(Map<String, dynamic> json) {
    return KeyAnalysisResult(
      trackId: json['track_id'] as String,
      source: json['source'] as String,
      keyName: json['key_name'] as String,
      camelot: json['camelot'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      isMajor: json['is_major'] as bool,
      analysisTimeMs: json['analysis_time_ms'] as int,
    );
  }
}

class SpectrogramBpmAnalysisResult {
  final String trackId;
  final String source;
  final double bpm;
  final int analysisTimeMs;
  final String spectrogramPath;
  final String analysisVisualizationPath;

  SpectrogramBpmAnalysisResult({
    required this.trackId,
    required this.source,
    required this.bpm,
    required this.analysisTimeMs,
    required this.spectrogramPath,
    required this.analysisVisualizationPath,
  });

  factory SpectrogramBpmAnalysisResult.fromJson(Map<String, dynamic> json) {
    return SpectrogramBpmAnalysisResult(
      trackId: json['track_id'] as String,
      source: json['source'] as String,
      bpm: (json['bpm'] as num).toDouble(),
      analysisTimeMs: json['analysis_time_ms'] as int,
      spectrogramPath: json['spectrogram_path'] as String,
      analysisVisualizationPath: json['analysis_visualization_path'] as String,
    );
  }
}

class BpmAnalysisResult {
  final String trackId;
  final String source;
  final double bpm;
  final int analysisTimeMs;

  BpmAnalysisResult({
    required this.trackId,
    required this.source,
    required this.bpm,
    required this.analysisTimeMs,
  });

  factory BpmAnalysisResult.fromJson(Map<String, dynamic> json) {
    return BpmAnalysisResult(
      trackId: json['track_id'] as String,
      source: json['source'] as String,
      bpm: (json['bpm'] as num).toDouble(),
      analysisTimeMs: json['analysis_time_ms'] as int,
    );
  }
}

class BpmResponse {
  final String trackId;
  final String source;
  final double? bpm;

  BpmResponse({
    required this.trackId,
    required this.source,
    this.bpm,
  });

  factory BpmResponse.fromJson(Map<String, dynamic> json) {
    return BpmResponse(
      trackId: json['track_id'] as String,
      source: json['source'] as String,
      bpm: json['bpm'] != null ? (json['bpm'] as num).toDouble() : null,
    );
  }
}
