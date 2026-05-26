import { createMMKV } from 'react-native-mmkv';

import type { MusicFolder } from '../types/music';

const SELECTED_FOLDER_KEY = 'settings.selectedMusicFolder';

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