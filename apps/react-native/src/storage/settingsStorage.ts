import { createMMKV } from 'react-native-mmkv';

import { DEFAULT_BACKEND_URL } from '../constants/backend';
import type { AuthSession } from '../types/auth';
import type { MusicFolder } from '../types/music';

const SELECTED_FOLDER_KEY = 'settings.selectedMusicFolder';
const BACKEND_URL_KEY = 'settings.backendUrl';
const AUTH_SESSION_KEY = 'settings.authSession';
const THEME_PREFERENCE_KEY = 'settings.themePreference';

export type ThemePreference = 'light' | 'dark';

export const settingsStorage = createMMKV({
  id: 'musestruct-native-settings',
});

export function getStoredMusicFolder(): MusicFolder | null {
  const serializedFolder = settingsStorage.getString(SELECTED_FOLDER_KEY);

  if (!serializedFolder) {
    return null;
  }

  try {
    return JSON.parse(serializedFolder) as MusicFolder;
  } catch {
    settingsStorage.remove(SELECTED_FOLDER_KEY);
    return null;
  }
}

export function persistMusicFolder(folder: MusicFolder | null) {
  if (!folder) {
    settingsStorage.remove(SELECTED_FOLDER_KEY);
    return;
  }

  settingsStorage.set(SELECTED_FOLDER_KEY, JSON.stringify(folder));
}

export function getStoredBackendUrl(): string {
  return settingsStorage.getString(BACKEND_URL_KEY) ?? DEFAULT_BACKEND_URL;
}

export function persistBackendUrl(backendUrl: string) {
  settingsStorage.set(BACKEND_URL_KEY, backendUrl);
}

export function getStoredAuthSession(): AuthSession | null {
  const serializedSession = settingsStorage.getString(AUTH_SESSION_KEY);

  if (!serializedSession) {
    return null;
  }

  try {
    return JSON.parse(serializedSession) as AuthSession;
  } catch {
    settingsStorage.remove(AUTH_SESSION_KEY);
    return null;
  }
}

export function persistAuthSession(session: AuthSession | null) {
  if (!session) {
    settingsStorage.remove(AUTH_SESSION_KEY);
    return;
  }

  settingsStorage.set(AUTH_SESSION_KEY, JSON.stringify(session));
}

export function getStoredThemePreference(): ThemePreference {
  const themePreference = settingsStorage.getString(THEME_PREFERENCE_KEY);

  if (themePreference === 'dark') {
    return 'dark';
  }

  return 'light';
}

export function persistThemePreference(themePreference: ThemePreference) {
  settingsStorage.set(THEME_PREFERENCE_KEY, themePreference);
}