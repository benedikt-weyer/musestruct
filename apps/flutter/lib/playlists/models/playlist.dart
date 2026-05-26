class Playlist {
  final String id;
  final String name;
  final String? description;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int itemCount;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
    required this.itemCount,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isPublic: json['is_public'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      itemCount: json['item_count'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'is_public': isPublic,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'item_count': itemCount,
    };
  }
}

class PlaylistItem {
  final String id;
  final String itemType; // "track" or "playlist"
  final String itemId;
  final int position;
  final DateTime addedAt;
  final String? title;
  final String? artist;
  final String? album;
  final int? duration;
  final String? source;
  final String? coverUrl;
  final bool isPlaylist;
  final String? playlistName;

  PlaylistItem({
    required this.id,
    required this.itemType,
    required this.itemId,
    required this.position,
    required this.addedAt,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.source,
    this.coverUrl,
    required this.isPlaylist,
    this.playlistName,
  });

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      id: json['id'] as String,
      itemType: json['item_type'] as String,
      itemId: json['item_id'] as String,
      position: json['position'] as int,
      addedAt: DateTime.parse(json['added_at'] as String),
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      duration: json['duration'] as int?,
      source: json['source'] as String?,
      coverUrl: json['cover_url'] as String?,
      isPlaylist: json['is_playlist'] as bool,
      playlistName: json['playlist_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_type': itemType,
      'item_id': itemId,
      'position': position,
      'added_at': addedAt.toIso8601String(),
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'source': source,
      'cover_url': coverUrl,
      'is_playlist': isPlaylist,
      'playlist_name': playlistName,
    };
  }

  String get displayTitle => title ?? playlistName ?? 'Unknown';
  String get displaySubtitle => isPlaylist ? 'Playlist' : '${artist ?? ''} • ${album ?? ''}'.trim();
  String get formattedDuration {
    if (duration == null) return '';
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class CreatePlaylistRequest {
  final String name;
  final String? description;
  final bool isPublic;

  CreatePlaylistRequest({
    required this.name,
    this.description,
    required this.isPublic,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'is_public': isPublic,
    };
  }
}

class UpdatePlaylistRequest {
  final String? name;
  final String? description;
  final bool? isPublic;

  UpdatePlaylistRequest({
    this.name,
    this.description,
    this.isPublic,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (name != null) json['name'] = name;
    if (description != null) json['description'] = description;
    if (isPublic != null) json['is_public'] = isPublic;
    return json;
  }
}

class AddPlaylistItemRequest {
  final String itemType; // "track" or "playlist"
  final String itemId;
  final int? position;
  // Track details (only used when itemType is "track")
  final String? title;
  final String? artist;
  final String? album;
  final int? duration;
  final String? source;
  final String? coverUrl;
  // Playlist details (only used when itemType is "playlist")
  final String? playlistName;

  AddPlaylistItemRequest({
    required this.itemType,
    required this.itemId,
    this.position,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.source,
    this.coverUrl,
    this.playlistName,
  });

  Map<String, dynamic> toJson() {
    return {
      'item_type': itemType,
      'item_id': itemId,
      'position': position,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'source': source,
      'cover_url': coverUrl,
      'playlist_name': playlistName,
    };
  }
}

class ReorderPlaylistItemRequest {
  final int newPosition;

  ReorderPlaylistItemRequest({
    required this.newPosition,
  });

  Map<String, dynamic> toJson() {
    return {
      'new_position': newPosition,
    };
  }
}

class PlaylistListResponse {
  final List<Playlist> playlists;
  final int total;
  final int page;
  final int perPage;

  PlaylistListResponse({
    required this.playlists,
    required this.total,
    required this.page,
    required this.perPage,
  });

  factory PlaylistListResponse.fromJson(Map<String, dynamic> json) {
    return PlaylistListResponse(
      playlists: (json['playlists'] as List)
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      perPage: json['per_page'] as int,
    );
  }
}
