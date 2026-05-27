import type { AuthSession } from '../types/auth';
import type {
  LibraryPlaylistListResponse,
  SavedAlbum,
  SavedTracksListResponse,
} from '../types/library';
import { normalizeBackendUrl } from './backendApi';

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

  return parseApiResponse<SavedTracksListResponse>(response);
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