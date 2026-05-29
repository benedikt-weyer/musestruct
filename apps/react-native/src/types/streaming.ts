export type StreamingTrack = {
  id: string;
  title: string;
  artist: string;
  album: string;
  duration?: number;
  stream_url?: string;
  cover_url?: string;
  quality?: string;
  source: string;
  bitrate?: number;
  sample_rate?: number;
  bit_depth?: number;
};

export type StreamingAlbum = {
  id: string;
  title: string;
  artist: string;
  release_date?: string;
  cover_url?: string;
  tracks: StreamingTrack[];
  source: string;
};

export type StreamingPlaylist = {
  id: string;
  name: string;
  description?: string;
  owner: string;
  source: string;
  cover_url?: string;
  track_count: number;
  is_public: boolean;
  external_url?: string;
};

export type StreamingSearchResults = {
  tracks: StreamingTrack[];
  albums: StreamingAlbum[];
  playlists: StreamingPlaylist[];
  total: number;
  offset: number;
  limit: number;
};

export type AvailableService = {
  name: string;
  display_name: string;
  supports_full_tracks: boolean;
  requires_premium: boolean;
};

export type AvailableServicesResponse = {
  services: AvailableService[];
};

export type ConnectedServiceInfo = {
  name: string;
  display_name: string;
  is_connected: boolean;
  connected_at?: string | null;
  account_username?: string | null;
};

export type ServiceStatusResponse = {
  services: ConnectedServiceInfo[];
};

export type SpotifyAuthUrlResponse = {
  auth_url: string;
  state: string;
};

export type SavedTrackPayload = {
  track_id: string;
  title: string;
  artist: string;
  album: string;
  duration: number;
  source: string;
  cover_url?: string;
};

export type ServerPreloadMode = 'recheck_all' | 'new_only';

export type ServerPreloadState = 'idle' | 'running' | 'completed' | 'failed';

export type ServerPreloadProgress = {
  state: ServerPreloadState;
  mode: ServerPreloadMode;
  phase: string;
  total_files: number;
  processed_files: number;
  current_item?: string | null;
  imported_tracks: number;
  updated_tracks: number;
  skipped_tracks: number;
  deleted_tracks: number;
  imported_albums: number;
  updated_albums: number;
  deleted_albums: number;
  imported_playlists: number;
  updated_playlists: number;
  deleted_playlists: number;
  canonical_tracks: number;
  canonical_albums: number;
  canonical_playlists: number;
  error_message?: string | null;
};