import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../../music/models/music.dart';

class AudioAnalysisService {
  final ApiService _apiService;

  AudioAnalysisService(this._apiService);

  /// Analyze BPM of a track
  Future<BpmAnalysisResult> analyzeBpm(Track track) async {
    try {
      final response = await _apiService.post(
        '/audio/analyze-bpm',
        queryParameters: {
          'track_id': track.id,
          'source': track.source,
          if (track.streamUrl != null) 'stream_url': track.streamUrl!,
        },
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
