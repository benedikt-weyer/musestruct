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
  persistAuthSession,
  persistBackendUrl,
  persistMusicFolder,
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

  const value = useMemo(
    () => ({
      selectedFolder: storedSelectedFolder,
      setSelectedFolder,
      backendUrl: storedBackendUrl,
      setBackendUrl,
      authSession: storedAuthSession,
      setAuthSession,
    }),
    [storedAuthSession, storedBackendUrl, storedSelectedFolder],
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