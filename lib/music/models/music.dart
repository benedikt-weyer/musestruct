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
      case 'server':
        return 'Server';
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
  final String? source;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.releaseDate,
    this.coverUrl,
    required this.tracks,
    this.source,
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
      source: json['source'] as String?,
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
      'source': source,
    };
  }
}

class SearchResults {
  final List<Track> tracks;
  final List<Album> albums;
  final List<PlaylistSearchResult>? playlists;
  final int total;
  final int offset;
  final int limit;

  SearchResults({
    required this.tracks,
    required this.albums,
    this.playlists,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    print('SearchResults.fromJson: Received json: $json');
    
    // Safely extract playlists with extensive error handling
    List<PlaylistSearchResult> playlists = [];
    try {
      if (json.containsKey('playlists') && json['playlists'] != null) {
        final playlistsData = json['playlists'];
        print('SearchResults.fromJson: playlists data type: ${playlistsData.runtimeType}');
        print('SearchResults.fromJson: playlists data: $playlistsData');
        
        if (playlistsData is List) {
          playlists = playlistsData
              .map((e) {
                try {
                  return PlaylistSearchResult.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  print('SearchResults.fromJson: Error parsing playlist item: $e');
                  return null;
                }
              })
              .where((e) => e != null)
              .cast<PlaylistSearchResult>()
              .toList();
        } else {
          print('SearchResults.fromJson: playlists is not a List, it is: ${playlistsData.runtimeType}');
        }
      } else {
        print('SearchResults.fromJson: playlists field missing or null');
      }
    } catch (e) {
      print('SearchResults.fromJson: Error processing playlists: $e');
      playlists = [];
    }
    
    final result = SearchResults(
      tracks: (json['tracks'] as List<dynamic>?)
          ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      albums: (json['albums'] as List<dynamic>?)
          ?.map((e) => Album.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      playlists: playlists, // Always use the list (empty or populated)
      total: (json['total'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
    );
    
    print('SearchResults.fromJson: Created SearchResults with ${result.playlists?.length ?? 0} playlists');
    return result;
  }

  Map<String, dynamic> toJson() {
    return {
      'tracks': tracks.map((e) => e.toJson()).toList(),
      'albums': albums.map((e) => e.toJson()).toList(),
      'playlists': playlists?.map((e) => e.toJson()).toList() ?? [],
      'total': total,
      'offset': offset,
      'limit': limit,
    };
  }
}

class PlaylistSearchResult {
  final String id;
  final String name;
  final String? description;
  final String owner;
  final String source;
  final String? coverUrl;
  final int trackCount;
  final bool isPublic;
  final String? externalUrl;

  PlaylistSearchResult({
    required this.id,
    required this.name,
    this.description,
    required this.owner,
    required this.source,
    this.coverUrl,
    required this.trackCount,
    required this.isPublic,
    this.externalUrl,
  });

  factory PlaylistSearchResult.fromJson(Map<String, dynamic> json) {
    try {
      print('PlaylistSearchResult.fromJson: Parsing playlist: $json');
      return PlaylistSearchResult(
        id: json['id'] as String? ?? 'unknown',
        name: json['name'] as String? ?? 'Unknown Playlist',
        description: json['description'] as String?,
        owner: json['owner'] as String? ?? 'Unknown',
        source: json['source'] as String? ?? 'unknown',
        coverUrl: json['cover_url'] as String?,
        trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
        isPublic: json['is_public'] as bool? ?? true,
        externalUrl: json['external_url'] as String?,
      );
    } catch (e) {
      print('PlaylistSearchResult.fromJson: Error parsing playlist: $e');
      // Return a default playlist if parsing fails
      return PlaylistSearchResult(
        id: 'error_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Error Loading Playlist',
        description: 'Failed to load playlist data',
        owner: 'Unknown',
        source: 'unknown',
        coverUrl: null,
        trackCount: 0,
        isPublic: false,
        externalUrl: null,
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'owner': owner,
      'source': source,
      'cover_url': coverUrl,
      'track_count': trackCount,
      'is_public': isPublic,
      'external_url': externalUrl,
    };
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
      case 'server':
        return 'Server';
      default:
        return source.isNotEmpty ? source.toUpperCase() : 'Streaming';
    }
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
      case 'server':
        return 'Server';
      default:
        return source;
    }
  }
}

class SavedAlbum {
  final String id;
  final String albumId;
  final String title;
  final String artist;
  final String? releaseDate;
  final String? coverUrl;
  final String source;
  final int trackCount;
  final DateTime createdAt;

  SavedAlbum({
    required this.id,
    required this.albumId,
    required this.title,
    required this.artist,
    this.releaseDate,
    this.coverUrl,
    required this.source,
    required this.trackCount,
    required this.createdAt,
  });

  factory SavedAlbum.fromJson(Map<String, dynamic> json) {
    return SavedAlbum(
      id: json['id'] as String,
      albumId: json['album_id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      releaseDate: json['release_date'] as String?,
      coverUrl: json['cover_url'] as String?,
      source: json['source'] as String,
      trackCount: json['track_count'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'album_id': albumId,
      'title': title,
      'artist': artist,
      'release_date': releaseDate,
      'cover_url': coverUrl,
      'source': source,
      'track_count': trackCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Convert SavedAlbum to Album for display and playback
  Album toAlbum() {
    return Album(
      id: albumId,
      title: title,
      artist: artist,
      releaseDate: releaseDate,
      coverUrl: coverUrl,
      tracks: [], // Tracks will be fetched separately when needed
    );
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
      case 'server':
        return 'Server';
      default:
        return source.isNotEmpty ? source.toUpperCase() : 'Streaming';
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

class SaveAlbumRequest {
  final String albumId;
  final String title;
  final String artist;
  final String? releaseDate;
  final String? coverUrl;
  final String source;
  final int trackCount;

  SaveAlbumRequest({
    required this.albumId,
    required this.title,
    required this.artist,
    this.releaseDate,
    this.coverUrl,
    required this.source,
    required this.trackCount,
  });

  factory SaveAlbumRequest.fromAlbum(Album album) {
    return SaveAlbumRequest(
      albumId: album.id,
      title: album.title,
      artist: album.artist,
      releaseDate: album.releaseDate,
      coverUrl: album.coverUrl,
      source: album.source ?? (album.tracks.isNotEmpty ? album.tracks.first.source : 'streaming'),
      trackCount: album.tracks.length,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'album_id': albumId,
      'title': title,
      'artist': artist,
      'release_date': releaseDate,
      'cover_url': coverUrl,
      'source': source,
      'track_count': trackCount,
    };
  }
}

class BackendStreamUrlResponse {
  final String streamUrl;
  final bool isCached;

  BackendStreamUrlResponse({
    required this.streamUrl,
    required this.isCached,
  });

  factory BackendStreamUrlResponse.fromJson(Map<String, dynamic> json) {
    return BackendStreamUrlResponse(
      streamUrl: json['stream_url'] as String,
      isCached: json['is_cached'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_url': streamUrl,
      'is_cached': isCached,
    };
  }
}

enum PlayMode {
  normal,
  shuffle,
}

enum LoopMode {
  once,
  twice,
  infinite,
}

enum SearchType {
  tracks,
  albums,
  playlists,
}

class PlaylistQueueItem {
  final String id;
  final String playlistId;
  final String playlistName;
  final String? playlistDescription;
  final String? coverUrl;
  final PlayMode playMode;
  final LoopMode loopMode;
  final List<String> trackOrder; // Track IDs in play order
  final int currentTrackIndex;
  final DateTime addedAt;
  
  // Current track details
  final String? currentTrackId;
  final String? currentTrackTitle;
  final String? currentTrackArtist;
  final String? currentTrackAlbum;
  final int? currentTrackDuration;
  final String? currentTrackSource;
  final String? currentTrackCoverUrl;

  PlaylistQueueItem({
    required this.id,
    required this.playlistId,
    required this.playlistName,
    this.playlistDescription,
    this.coverUrl,
    required this.playMode,
    required this.loopMode,
    required this.trackOrder,
    required this.currentTrackIndex,
    required this.addedAt,
    this.currentTrackId,
    this.currentTrackTitle,
    this.currentTrackArtist,
    this.currentTrackAlbum,
    this.currentTrackDuration,
    this.currentTrackSource,
    this.currentTrackCoverUrl,
  });

  factory PlaylistQueueItem.fromJson(Map<String, dynamic> json) {
    return PlaylistQueueItem(
      id: json['id'] as String,
      playlistId: json['playlist_id'] as String,
      playlistName: json['playlist_name'] as String,
      playlistDescription: json['playlist_description'] as String?,
      coverUrl: json['cover_url'] as String?,
      playMode: PlayMode.values.firstWhere(
        (e) => e.name == json['play_mode'],
        orElse: () => PlayMode.normal,
      ),
      loopMode: LoopMode.values.firstWhere(
        (e) => e.name == json['loop_mode'],
        orElse: () => LoopMode.once,
      ),
      trackOrder: List<String>.from(json['track_order'] as List),
      currentTrackIndex: json['current_track_index'] as int,
      addedAt: DateTime.parse(json['added_at'] as String),
      currentTrackId: json['current_track_id'] as String?,
      currentTrackTitle: json['current_track_title'] as String?,
      currentTrackArtist: json['current_track_artist'] as String?,
      currentTrackAlbum: json['current_track_album'] as String?,
      currentTrackDuration: json['current_track_duration'] as int?,
      currentTrackSource: json['current_track_source'] as String?,
      currentTrackCoverUrl: json['current_track_cover_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'playlist_id': playlistId,
      'playlist_name': playlistName,
      'playlist_description': playlistDescription,
      'cover_url': coverUrl,
      'play_mode': playMode.name,
      'loop_mode': loopMode.name,
      'track_order': trackOrder,
      'current_track_index': currentTrackIndex,
      'added_at': addedAt.toIso8601String(),
      'current_track_id': currentTrackId,
      'current_track_title': currentTrackTitle,
      'current_track_artist': currentTrackArtist,
      'current_track_album': currentTrackAlbum,
      'current_track_duration': currentTrackDuration,
      'current_track_source': currentTrackSource,
      'current_track_cover_url': currentTrackCoverUrl,
    };
  }

  PlaylistQueueItem copyWith({
    String? id,
    String? playlistId,
    String? playlistName,
    String? playlistDescription,
    String? coverUrl,
    PlayMode? playMode,
    LoopMode? loopMode,
    List<String>? trackOrder,
    int? currentTrackIndex,
    DateTime? addedAt,
    String? currentTrackId,
    String? currentTrackTitle,
    String? currentTrackArtist,
    String? currentTrackAlbum,
    int? currentTrackDuration,
    String? currentTrackSource,
    String? currentTrackCoverUrl,
  }) {
    return PlaylistQueueItem(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      playlistName: playlistName ?? this.playlistName,
      playlistDescription: playlistDescription ?? this.playlistDescription,
      coverUrl: coverUrl ?? this.coverUrl,
      playMode: playMode ?? this.playMode,
      loopMode: loopMode ?? this.loopMode,
      trackOrder: trackOrder ?? this.trackOrder,
      currentTrackIndex: currentTrackIndex ?? this.currentTrackIndex,
      addedAt: addedAt ?? this.addedAt,
      currentTrackId: currentTrackId ?? this.currentTrackId,
      currentTrackTitle: currentTrackTitle ?? this.currentTrackTitle,
      currentTrackArtist: currentTrackArtist ?? this.currentTrackArtist,
      currentTrackAlbum: currentTrackAlbum ?? this.currentTrackAlbum,
      currentTrackDuration: currentTrackDuration ?? this.currentTrackDuration,
      currentTrackSource: currentTrackSource ?? this.currentTrackSource,
      currentTrackCoverUrl: currentTrackCoverUrl ?? this.currentTrackCoverUrl,
    );
  }
}
