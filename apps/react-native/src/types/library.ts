export type SavedTrack = {
  id: string;
  canonical_track_id: string;
  track_id: string;
  title: string;
  artist: string;
  album: string;
  duration?: number | null;
  source: string;
  cover_url?: string | null;
  is_favourite: boolean;
  created_at: string;
  updated_at: string;
};

export type FavouriteTrack = {
  id: string;
  user_track_id: string;
  canonical_track_id: string;
  track_id: string;
  title: string;
  artist: string;
  album: string;
  duration?: number | null;
  source: string;
  cover_url?: string | null;
  created_at: string;
  updated_at: string;
};

export type SavedTracksListResponse = {
  tracks: SavedTrack[];
  total_count: number;
  page: number;
  limit: number;
};

export type FavouriteTracksListResponse = {
  tracks: FavouriteTrack[];
  total_count: number;
  page: number;
  limit: number;
};

export type LastPlayedTrack = {
  id: string;
  canonical_track_id: string;
  track_id: string;
  title: string;
  artist: string;
  album: string;
  duration?: number | null;
  source: string;
  cover_url?: string | null;
  played_at: string;
  created_at: string;
  updated_at: string;
};

export type LastPlayedTracksListResponse = {
  tracks: LastPlayedTrack[];
  limit: number;
};

export type LibraryPlaylist = {
  id: string;
  canonical_playlist_id?: string | null;
  name: string;
  description?: string | null;
  source?: string | null;
  provider_playlist_id?: string | null;
  is_public: boolean;
  is_read_only: boolean;
  is_watched: boolean;
  last_synced_at?: string | null;
  created_at: string;
  updated_at: string;
  item_count: number;
  preview_cover_urls: string[];
};

export type LibraryPlaylistItem = {
  id: string;
  item_type: string;
  item_id: string;
  user_track_id?: string | null;
  position: number;
  added_at: string;
  title?: string | null;
  artist?: string | null;
  album?: string | null;
  duration?: number | null;
  source?: string | null;
  cover_url?: string | null;
  is_playlist: boolean;
  playlist_name?: string | null;
};

export type LibraryPlaylistListResponse = {
  playlists: LibraryPlaylist[];
  total: number;
  page: number;
  per_page: number;
};

export type LibrarySection = 'playlists' | 'tracks' | 'favourites' | 'local';