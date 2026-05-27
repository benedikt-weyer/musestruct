export type SavedTrack = {
  id: string;
  track_id: string;
  title: string;
  artist: string;
  album: string;
  duration: number;
  source: string;
  cover_url?: string | null;
  bpm?: number | null;
  created_at: string;
};

export type SavedTracksListResponse = {
  tracks: SavedTrack[];
  total_count: number;
  page: number;
  limit: number;
};

export type SavedAlbum = {
  id: string;
  album_id: string;
  title: string;
  artist: string;
  release_date?: string | null;
  cover_url?: string | null;
  source: string;
  track_count: number;
  created_at: string;
};

export type LibraryPlaylist = {
  id: string;
  name: string;
  description?: string | null;
  is_public: boolean;
  created_at: string;
  updated_at: string;
  item_count: number;
};

export type LibraryPlaylistListResponse = {
  playlists: LibraryPlaylist[];
  total: number;
  page: number;
  per_page: number;
};

export type LibrarySection = 'playlists' | 'albums' | 'tracks' | 'favourites';