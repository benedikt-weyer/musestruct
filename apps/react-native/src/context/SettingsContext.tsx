import { createContext, useContext, useState, type PropsWithChildren } from 'react';

import { getStoredMusicFolder, persistMusicFolder } from '../storage/settingsStorage';
import type { MusicFolder } from '../types/music';

type SettingsContextValue = {
  selectedFolder: MusicFolder | null;
  setSelectedFolder: (folder: MusicFolder | null) => void;
};

const SettingsContext = createContext<SettingsContextValue | null>(null);

export function SettingsProvider({ children }: PropsWithChildren) {
  const [selectedFolder, setSelectedFolderState] = useState<MusicFolder | null>(() =>
    getStoredMusicFolder(),
  );

  function setSelectedFolder(folder: MusicFolder | null) {
    persistMusicFolder(folder);
    setSelectedFolderState(folder);
  }

  return (
    <SettingsContext.Provider value={{ selectedFolder, setSelectedFolder }}>
      {children}
    </SettingsContext.Provider>
  );
}

export function useSettings() {
  const context = useContext(SettingsContext);

  if (!context) {
    throw new Error('useSettings must be used within a SettingsProvider.');
  }

  return context;
}