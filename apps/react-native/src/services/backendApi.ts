import type { AuthSession, BackendUser } from '../types/auth';

type ApiResponse<T> = {
  success: boolean;
  data: T | null;
  message: string | null;
};

type LoginResponse = {
  user: BackendUser;
  session_token: string;
};

type LoginPayload = {
  email: string;
  password: string;
};

type RegisterPayload = {
  email: string;
  username: string;
  password: string;
};

type ConnectionResult = {
  message: string;
};

export function normalizeBackendUrl(backendUrl: string) {
  return backendUrl.trim().replace(/\/+$/, '');
}

async function parseApiResponse<T>(response: Response) {
  const payload = (await response.json()) as ApiResponse<T>;

  if (!response.ok || !payload.success || !payload.data) {
    throw new Error(payload.message ?? `Request failed with status ${response.status}.`);
  }

  return payload.data;
}

export async function testBackendConnection(backendUrl: string): Promise<ConnectionResult> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/health`);
  const body = await response.text();

  if (!response.ok) {
    throw new Error(`Health check failed with status ${response.status}.`);
  }

  if (body.trim() !== 'OK') {
    throw new Error('The backend responded, but the health check payload was unexpected.');
  }

  return {
    message: 'Backend connection successful.',
  };
}

export async function loginWithBackend(
  backendUrl: string,
  payload: LoginPayload,
): Promise<AuthSession> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const data = await parseApiResponse<LoginResponse>(response);

  return {
    user: data.user,
    sessionToken: data.session_token,
  };
}

export async function registerWithBackend(
  backendUrl: string,
  payload: RegisterPayload,
): Promise<BackendUser> {
  const normalizedUrl = normalizeBackendUrl(backendUrl);
  const response = await fetch(`${normalizedUrl}/api/auth/register`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  return parseApiResponse<BackendUser>(response);
}