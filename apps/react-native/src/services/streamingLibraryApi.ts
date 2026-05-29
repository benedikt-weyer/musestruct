import type { AuthSession } from '../types/auth';
import type {
  AvailableServicesResponse,
  SavedTrackPayload,
  ServerPreloadMode,
  ServerPreloadProgress,
  ServiceStatusResponse,
  SpotifyAuthUrlResponse,
  StreamingTrack,
  StreamingSearchResults,
} from '../types/streaming';
import { normalizeBackendUrl } from './backendApi';

type ApiResponse<T> = {
  success: boolean;
  data: T | null;
  message: string | null;
};

type SearchOptions = {
  services?: string[];
  type?: 'all' | 'track' | 'album' | 'playlist';
  library?: boolean;
  limit?: number;
  offset?: number;
};

async function parseApiResponse<T>(response: Response) {
  const payload = (await response.json()) as ApiResponse<T>;

  if (!response.ok || !payload.success || payload.data === null) {
    throw new Error(payload.message ?? `Request failed with status ${response.status}.`);
  }

  return payload.data;
}

function createAuthHeaders(authSession: AuthSession) {
  return {
    Authorization: `Bearer ${authSession.sessionToken}`,
    'Content-Type': 'application/json',
  };
}

function createSearchQuery(query: string, options: SearchOptions) {
  const searchParams = new URLSearchParams();
  searchParams.set('q', query);

  if (options.type && options.type !== 'all') {
    searchParams.set('type', options.type);
  }

  if (options.library) {
    searchParams.set('library', 'true');
  }

  if (typeof options.limit === 'number') {
    searchParams.set('limit', options.limit.toString());
  }

  if (typeof options.offset === 'number') {
    searchParams.set('offset', options.offset.toString());
  }

  options.services?.forEach((serviceName) => {
    searchParams.append('services', serviceName);
  });

  return searchParams.toString();
}

function absolutizeStreamUrl(backendUrl: string, streamUrl?: string | null) {
  if (!streamUrl) {
    return streamUrl ?? undefined;
  }

  try {
    return new URL(streamUrl, backendUrl).toString();
  } catch {
    return streamUrl;
  }
}

function normalizeStreamingTrackUrls(backendUrl: string, track: StreamingTrack): StreamingTrack {
  return {
    ...track,
    stream_url: absolutizeStreamUrl(backendUrl, track.stream_url),
  };
}

function normalizeStreamingSearchResults(
  backendUrl: string,
  results: StreamingSearchResults,
): StreamingSearchResults {
  return {
    ...results,
    tracks: results.tracks.map((track) => normalizeStreamingTrackUrls(backendUrl, track)),
    albums: results.albums.map((album) => ({
      ...album,
      tracks: album.tracks.map((track) => normalizeStreamingTrackUrls(backendUrl, track)),
    })),
  };
}

export async function fetchAvailableServices(
  backendUrl: string,
  authSession: AuthSession,
): Promise<AvailableServicesResponse> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/streaming/services`, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<AvailableServicesResponse>(response);
}

export async function fetchServiceStatus(
  backendUrl: string,
  authSession: AuthSession,
): Promise<ServiceStatusResponse> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/streaming/status`, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<ServiceStatusResponse>(response);
}

export async function searchStreamingCatalog(
  backendUrl: string,
  authSession: AuthSession,
  query: string,
  options: SearchOptions = {},
): Promise<StreamingSearchResults> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const queryString = createSearchQuery(query, options);
  const response = await fetch(`${normalizedUrl}/api/streaming/search?${queryString}`, {
    headers: createAuthHeaders(authSession),
  });

  const results = await parseApiResponse<StreamingSearchResults>(response);
  return normalizeStreamingSearchResults(normalizedUrl, results);
}

export async function saveTrackToLibrary(
  backendUrl: string,
  authSession: AuthSession,
  payload: SavedTrackPayload,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/saved-tracks`, {
    method: 'POST',
    headers: createAuthHeaders(authSession),
    body: JSON.stringify(payload),
  });

  return parseApiResponse<unknown>(response);
}

export async function connectQobuzProvider(
  backendUrl: string,
  authSession: AuthSession,
  username: string,
  password: string,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/streaming/connect/qobuz`, {
    method: 'POST',
    headers: createAuthHeaders(authSession),
    body: JSON.stringify({
      username,
      password,
    }),
  });

  return parseApiResponse<string>(response);
}

export async function fetchSpotifyAuthUrl(
  backendUrl: string,
  authSession: AuthSession,
  redirectUrl?: string,
): Promise<SpotifyAuthUrlResponse> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams();

  if (redirectUrl) {
    searchParams.set('redirect_url', redirectUrl);
  }

  const requestUrl = searchParams.size
    ? `${normalizedUrl}/api/streaming/spotify/auth-url?${searchParams.toString()}`
    : `${normalizedUrl}/api/streaming/spotify/auth-url`;
  const response = await fetch(requestUrl, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<SpotifyAuthUrlResponse>(response);
}

export async function fetchTidalAuthUrl(
  backendUrl: string,
  authSession: AuthSession,
  redirectUrl?: string,
): Promise<SpotifyAuthUrlResponse> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams();

  if (redirectUrl) {
    searchParams.set('redirect_url', redirectUrl);
  }

  const requestUrl = searchParams.size
    ? `${normalizedUrl}/api/streaming/tidal/auth-url?${searchParams.toString()}`
    : `${normalizedUrl}/api/streaming/tidal/auth-url`;
  const response = await fetch(requestUrl, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<SpotifyAuthUrlResponse>(response);
}

export async function disconnectStreamingProvider(
  backendUrl: string,
  authSession: AuthSession,
  serviceName: 'qobuz' | 'spotify' | 'tidal',
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/streaming/disconnect`, {
    method: 'POST',
    headers: createAuthHeaders(authSession),
    body: JSON.stringify({
      service_name: serviceName,
    }),
  });

  return parseApiResponse<string>(response);
}

export async function fetchTrackStreamUrl(
  backendUrl: string,
  authSession: AuthSession,
  trackId: string,
  service: string,
  quality?: string,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams({
    track_id: trackId,
    service,
  });

  if (quality) {
    searchParams.set('quality', quality);
  }

  const response = await fetch(
    `${normalizedUrl}/api/streaming/stream-url?${searchParams.toString()}`,
    {
      headers: createAuthHeaders(authSession),
    },
  );

  const streamUrl = await parseApiResponse<string>(response);
  return absolutizeStreamUrl(normalizedUrl, streamUrl) ?? streamUrl;
}

export async function fetchStreamingTrack(
  backendUrl: string,
  authSession: AuthSession,
  trackId: string,
  service: string,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams({
    track_id: trackId,
    service,
  });

  const response = await fetch(`${normalizedUrl}/api/streaming/track?${searchParams.toString()}`, {
    headers: createAuthHeaders(authSession),
  });

  const track = await parseApiResponse<StreamingTrack>(response);
  return normalizeStreamingTrackUrls(normalizedUrl, track);
}

export async function fetchStreamingPlaylistTracks(
  backendUrl: string,
  authSession: AuthSession,
  playlistId: string,
  service: string,
  limit?: number,
  offset?: number,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const searchParams = new URLSearchParams({
    service,
  });

  if (typeof limit === 'number') {
    searchParams.set('limit', limit.toString());
  }

  if (typeof offset === 'number') {
    searchParams.set('offset', offset.toString());
  }

  const response = await fetch(
    `${normalizedUrl}/api/streaming/playlist/${playlistId}/tracks?${searchParams.toString()}`,
    {
      headers: createAuthHeaders(authSession),
    },
  );

  const tracks = await parseApiResponse<StreamingTrack[]>(response);
  return tracks.map((track) => normalizeStreamingTrackUrls(normalizedUrl, track));
}

export async function fetchServerPreloadStatus(
  backendUrl: string,
  authSession: AuthSession,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/library/server-preload`, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<ServerPreloadProgress>(response);
}

export async function startServerPreload(
  backendUrl: string,
  authSession: AuthSession,
  mode: ServerPreloadMode,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/library/server-preload`, {
    method: 'POST',
    headers: createAuthHeaders(authSession),
    body: JSON.stringify({ mode }),
  });

  return parseApiResponse<ServerPreloadProgress>(response);
}