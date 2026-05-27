import type { AuthSession } from '../types/auth';
import type {
  AvailableServicesResponse,
  SavedAlbumPayload,
  SavedTrackPayload,
  ServiceStatusResponse,
  SpotifyAuthUrlResponse,
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
  type?: 'track' | 'album' | 'playlist';
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

  if (options.type) {
    searchParams.set('type', options.type);
  }

  if (typeof options.limit === 'number') {
    searchParams.set('limit', options.limit.toString());
  }

  if (typeof options.offset === 'number') {
    searchParams.set('offset', options.offset.toString());
  }

  options.services?.forEach((serviceName, index) => {
    searchParams.set(`services[${index}]`, serviceName);
  });

  return searchParams.toString();
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

  return parseApiResponse<StreamingSearchResults>(response);
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

export async function saveAlbumToLibrary(
  backendUrl: string,
  authSession: AuthSession,
  payload: SavedAlbumPayload,
) {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/albums/save`, {
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
): Promise<SpotifyAuthUrlResponse> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/streaming/spotify/auth-url`, {
    headers: createAuthHeaders(authSession),
  });

  return parseApiResponse<SpotifyAuthUrlResponse>(response);
}

export async function disconnectStreamingProvider(
  backendUrl: string,
  authSession: AuthSession,
  serviceName: 'qobuz' | 'spotify',
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