import {
  createContext,
  useContext,
  useMemo,
  useState,
  type PropsWithChildren,
} from 'react';

import {
  getStoredAuthSession,
  getStoredBackendUrl,
  getStoredMusicFolder,
  getStoredThemePreference,
  persistAuthSession,
  persistBackendUrl,
  persistMusicFolder,
  persistThemePreference,
  type ThemePreference,
} from '../storage/settingsStorage';
import type { AuthSession } from '../types/auth';
import type { MusicFolder } from '../types/music';

type SettingsContextValue = {
  selectedFolder: MusicFolder | null;
  setSelectedFolder: (folder: MusicFolder | null) => void;
  backendUrl: string;
  setBackendUrl: (backendUrl: string) => void;
  authSession: AuthSession | null;
  setAuthSession: (session: AuthSession | null) => void;
  themePreference: ThemePreference;
  setThemePreference: (themePreference: ThemePreference) => void;
};

const SettingsContext = createContext<SettingsContextValue | null>(null);

export function SettingsProvider({ children }: Readonly<PropsWithChildren>) {
  const [storedSelectedFolder, setStoredSelectedFolder] = useState<MusicFolder | null>(() =>
    getStoredMusicFolder(),
  );
  const [storedBackendUrl, setStoredBackendUrl] = useState<string>(() => getStoredBackendUrl());
  const [storedAuthSession, setStoredAuthSession] = useState<AuthSession | null>(() =>
    getStoredAuthSession(),
  );
  const [storedThemePreference, setStoredThemePreference] = useState<ThemePreference>(() =>
    getStoredThemePreference(),
  );

  function setSelectedFolder(folder: MusicFolder | null) {
    persistMusicFolder(folder);
    setStoredSelectedFolder(folder);
  }

  function setBackendUrl(backendUrlValue: string) {
    persistBackendUrl(backendUrlValue);
    setStoredBackendUrl(backendUrlValue);
  }

  function setAuthSession(session: AuthSession | null) {
    persistAuthSession(session);
    setStoredAuthSession(session);
  }

  function setThemePreference(themePreference: ThemePreference) {
    persistThemePreference(themePreference);
    setStoredThemePreference(themePreference);
  }

  const value = useMemo(
    () => ({
      selectedFolder: storedSelectedFolder,
      setSelectedFolder,
      backendUrl: storedBackendUrl,
      setBackendUrl,
      authSession: storedAuthSession,
      setAuthSession,
      themePreference: storedThemePreference,
      setThemePreference,
    }),
    [storedAuthSession, storedBackendUrl, storedSelectedFolder, storedThemePreference],
  );

  return (
    <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>
  );
}

export function useSettings() {
  const context = useContext(SettingsContext);

  if (!context) {
    throw new Error('useSettings must be used within a SettingsProvider.');
  }

  return context;
}