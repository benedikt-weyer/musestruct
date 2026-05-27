import type { AuthSession } from '../types/auth';
import type {
  LibraryPlaylistListResponse,
  LibraryPlaylist,
  LibraryPlaylistItem,
  SavedAlbum,
  SavedTrack,
  SavedTracksListResponse,
} from '../types/library';
import { normalizeBackendUrl } from './backendApi';
import { fetchStreamingTrack } from './streamingLibraryApi';

type ApiResponse<T> = {
  success: boolean;
  data: T | null;
  message: string | null;
};

function createAuthHeaders(authSession: AuthSession) {
  return {
    Authorization: `Bearer ${authSession.sessionToken}`,
    'Content-Type': 'application/json',
  };
}

async function parseApiResponse<T>(response: Response) {
  const payload = (await response.json()) as ApiResponse<T>;

  if (!response.ok || !payload.success || payload.data === null) {
    throw new Error(payload.message ?? `Request failed with status ${response.status}.`);
  }

  return payload.data;
}

async function parseMutationResponse(response: Response) {
  const payload = (await response.json()) as ApiResponse<unknown>;

  if (!response.ok || !payload.success) {
    throw new Error(payload.message ?? `Request failed with status ${response.status}.`);
  }

  if (typeof payload.data === 'string' && payload.data.length > 0) {
    return payload.data;
  }

  if (payload.message) {
    return payload.message;
  }

  return null;
}

function hasStaleTidalMetadata(track: {
  artist?: string | null;
  album?: string | null;
  cover_url?: string | null;
  source?: string | null;
}) {
  return (
    track.source === 'tidal' &&
    (track.artist === 'Unknown Artist' || track.album === 'Unknown Album' || !track.cover_url)
  );
}

async function refreshSavedTidalTrackMetadata(
  backendUrl: string,
  authSession: AuthSession,
  track: SavedTrack,
): Promise<SavedTrack> {
  if (!hasStaleTidalMetadata(track)) {
    return track;
  }

  try {
    const liveTrack = await fetchStreamingTrack(backendUrl, authSession, track.track_id, 'tidal');
    return {
      ...track,
      title: liveTrack.title || track.title,
      artist: liveTrack.artist || track.artist,
      album: liveTrack.album || track.album,
      duration: liveTrack.duration ?? track.duration,
      cover_url: liveTrack.cover_url ?? track.cover_url,
    };
  } catch {
    return track;
  }
}

async function refreshPlaylistItemTidalMetadata(
  backendUrl: string,
  authSession: AuthSession,
  item: LibraryPlaylistItem,
): Promise<LibraryPlaylistItem> {
  if (item.is_playlist || item.source !== 'tidal' || !hasStaleTidalMetadata(item)) {
    return item;
  }

  try {
    const liveTrack = await fetchStreamingTrack(backendUrl, authSession, item.item_id, 'tidal');
    return {
      ...item,
      title: liveTrack.title || item.title,
      artist: liveTrack.artist || item.artist,
      album: liveTrack.album || item.album,
      duration: liveTrack.duration ?? item.duration,
      cover_url: liveTrack.cover_url ?? item.cover_url,
    };
  } catch {
    return item;
  }
}

export async function fetchSavedTracks(
  backendUrl: string,
  authSession: AuthSession,
  page = 1,
  limit = 100,
): Promise<SavedTracksListResponse> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams({
    page: page.toString(),
    limit: limit.toString(),
  });
  const response = await fetch(`${normalizedUrl}/api/saved-tracks?${searchParams.toString()}`, {
    headers: createAuthHeaders(authSession),
  });

  const payload = await parseApiResponse<SavedTracksListResponse>(response);

  return {
    ...payload,
    tracks: await Promise.all(
      payload.tracks.map((track) => refreshSavedTidalTrackMetadata(backendUrl, authSession, track)),
    ),
  };
}

export async function fetchSavedAlbums(
  backendUrl: string,
  authSession: AuthSession,
  page = 1,
  limit = 100,
): Promise<SavedAlbum[]> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams({
    page: page.toString(),
    limit: limit.toString(),
  });
  const response = await fetch(`${normalizedUrl}/api/albums/saved?${searchParams.toString()}`, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<SavedAlbum[]>(response);
}

export async function fetchLibraryPlaylists(
  backendUrl: string,
  authSession: AuthSession,
  page = 1,
  perPage = 100,
): Promise<LibraryPlaylistListResponse> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams({
    page: page.toString(),
    per_page: perPage.toString(),
  });
  const response = await fetch(`${normalizedUrl}/api/v2/playlists?${searchParams.toString()}`, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<LibraryPlaylistListResponse>(response);
}

export async function fetchLibraryPlaylistItems(
  backendUrl: string,
  authSession: AuthSession,
  playlistId: string,
): Promise<LibraryPlaylistItem[]> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/v2/playlists/${playlistId}/items`, {
    headers: createAuthHeaders(authSession),
  });

  const items = await parseApiResponse<LibraryPlaylistItem[]>(response);
  return Promise.all(
    items.map((item) => refreshPlaylistItemTidalMetadata(backendUrl, authSession, item)),
  );
}

export async function createLibraryPlaylist(
  backendUrl: string,
  authSession: AuthSession,
  payload: {
    name: string;
    description?: string | null;
    is_public: boolean;
  },
): Promise<LibraryPlaylist> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/v2/playlists`, {
    method: 'POST',
    headers: createAuthHeaders(authSession),
    body: JSON.stringify(payload),
  });

  return parseApiResponse<LibraryPlaylist>(response);
}

export async function addLibraryPlaylistItem(
  backendUrl: string,
  authSession: AuthSession,
  playlistId: string,
  payload: {
    item_type: 'track' | 'playlist';
    item_id: string;
    position?: number;
    title?: string | null;
    artist?: string | null;
    album?: string | null;
    duration?: number | null;
    source?: string | null;
    cover_url?: string | null;
    playlist_name?: string | null;
  },
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/v2/playlists/${playlistId}/items`, {
    method: 'POST',
    headers: createAuthHeaders(authSession),
    body: JSON.stringify(payload),
  });

  return parseApiResponse<LibraryPlaylistItem>(response);
}

export async function deleteSavedTrack(
  backendUrl: string,
  authSession: AuthSession,
  id: string,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/saved-tracks/${id}`, {
    method: 'DELETE',
    headers: createAuthHeaders(authSession),
  });

  return parseMutationResponse(response);
}

export async function deleteSavedAlbum(
  backendUrl: string,
  authSession: AuthSession,
  id: string,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/albums/saved/${id}`, {
    method: 'DELETE',
    headers: createAuthHeaders(authSession),
  });

  return parseMutationResponse(response);
}

export async function deleteLibraryPlaylist(
  backendUrl: string,
  authSession: AuthSession,
  id: string,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/v2/playlists/${id}`, {
    method: 'DELETE',
    headers: createAuthHeaders(authSession),
  });

  return parseMutationResponse(response);
}