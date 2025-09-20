class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int? duration;
  final String? streamUrl;
  final String? coverUrl;
  final String source;
  final String? quality;
  final int? bitrate;      // in kbps
  final int? sampleRate;   // in Hz
  final int? bitDepth;     // in bits

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.duration,
    this.streamUrl,
    this.coverUrl,
    required this.source,
    this.quality,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Unknown Album',
      duration: json['duration'] as int?,
      streamUrl: json['stream_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      source: json['source']?.toString() ?? 'streaming',
      quality: json['quality'] as String?,
      bitrate: json['bitrate'] as int?,
      sampleRate: json['sample_rate'] as int?,
      bitDepth: json['bit_depth'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'streamUrl': streamUrl,
      'coverUrl': coverUrl,
      'source': source,
      'quality': quality,
      'bitrate': bitrate,
      'sample_rate': sampleRate,
      'bit_depth': bitDepth,
    };
  }

  String get formattedDuration {
    if (duration == null) return '';
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedQuality {
    List<String> parts = [];
    
    if (bitrate != null) {
      parts.add('${bitrate} kbps');
    }
    
    if (sampleRate != null && bitDepth != null) {
      parts.add('${(sampleRate! / 1000).toStringAsFixed(1)}kHz/${bitDepth}bit');
    } else if (sampleRate != null) {
      parts.add('${(sampleRate! / 1000).toStringAsFixed(1)}kHz');
    }
    
    if (quality != null && parts.isEmpty) {
      parts.add(quality!);
    }
    
    return parts.join(' • ');
  }

  String get formattedSource {
    switch (source.toLowerCase()) {
      case 'qobuz':
        return 'Qobuz';
      case 'spotify':
        return 'Spotify';
      case 'tidal':
        return 'Tidal';
      case 'apple_music':
        return 'Apple Music';
      case 'youtube_music':
        return 'YouTube Music';
      case 'deezer':
        return 'Deezer';
      default:
        return source.isNotEmpty ? source.toUpperCase() : 'Streaming';
    }
  }
}

// Real-time audio information from the audio player
class AudioOutputInfo {
  final int? outputBitrate;     // Actual output bitrate in kbps
  final int? outputSampleRate;  // Actual output sample rate in Hz
  final int? outputBitDepth;    // Actual output bit depth
  final String? format;         // Audio format (MP3, FLAC, etc.)
  final String? codec;          // Audio codec
  
  AudioOutputInfo({
    this.outputBitrate,
    this.outputSampleRate,
    this.outputBitDepth,
    this.format,
    this.codec,
  });
  
  String get formattedOutputQuality {
    List<String> parts = [];
    
    if (outputBitrate != null) {
      parts.add('${outputBitrate} kbps');
    }
    
    if (outputSampleRate != null && outputBitDepth != null) {
      parts.add('${(outputSampleRate! / 1000).toStringAsFixed(1)}kHz/${outputBitDepth}bit');
    } else if (outputSampleRate != null) {
      parts.add('${(outputSampleRate! / 1000).toStringAsFixed(1)}kHz');
    }
    
    if (format != null) {
      parts.add(format!.toUpperCase());
    }
    
    return parts.join(' • ');
  }
  
  bool get hasInfo => outputBitrate != null || outputSampleRate != null || format != null;
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String? releaseDate;
  final String? coverUrl;
  final List<Track> tracks;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.releaseDate,
    this.coverUrl,
    required this.tracks,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Album',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      releaseDate: json['release_date'] as String?,
      coverUrl: json['cover_url'] as String?,
      tracks: (json['tracks'] as List<dynamic>?)
          ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'releaseDate': releaseDate,
      'coverUrl': coverUrl,
      'tracks': tracks.map((e) => e.toJson()).toList(),
    };
  }
}

class SearchResults {
  final List<Track> tracks;
  final List<Album> albums;
  final int total;
  final int offset;
  final int limit;

  SearchResults({
    required this.tracks,
    required this.albums,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    return SearchResults(
      tracks: (json['tracks'] as List<dynamic>?)
          ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      albums: (json['albums'] as List<dynamic>?)
          ?.map((e) => Album.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      total: (json['total'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tracks': tracks.map((e) => e.toJson()).toList(),
      'albums': albums.map((e) => e.toJson()).toList(),
      'total': total,
      'offset': offset,
      'limit': limit,
    };
  }
}

class Playlist {
  final String id;
  final String name;
  final String? description;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isPublic: json['isPublic'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'isPublic': isPublic,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class SavedTrack {
  final String id;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final int duration;
  final String source;
  final String? coverUrl;
  final DateTime createdAt;

  SavedTrack({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.source,
    this.coverUrl,
    required this.createdAt,
  });

  factory SavedTrack.fromJson(Map<String, dynamic> json) {
    return SavedTrack(
      id: json['id'] as String,
      trackId: json['track_id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      duration: json['duration'] as int,
      source: json['source'] as String,
      coverUrl: json['cover_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'track_id': trackId,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'source': source,
      'cover_url': coverUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Convert SavedTrack to Track for playback
  Track toTrack() {
    return Track(
      id: trackId,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      streamUrl: null, // Will be fetched when playing
      coverUrl: coverUrl,
      source: source,
      quality: null,
      bitrate: null,
      sampleRate: null,
      bitDepth: null,
    );
  }

  String get formattedSource {
    switch (source.toLowerCase()) {
      case 'spotify':
        return 'Spotify';
      case 'qobuz':
        return 'Qobuz';
      default:
        return source;
    }
  }
}

class SaveTrackRequest {
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final int duration;
  final String source;
  final String? coverUrl;

  SaveTrackRequest({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.source,
    this.coverUrl,
  });

  factory SaveTrackRequest.fromTrack(Track track) {
    return SaveTrackRequest(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration ?? 0,
      source: track.source,
      coverUrl: track.coverUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'track_id': trackId,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'source': source,
      'cover_url': coverUrl,
    };
  }
}
