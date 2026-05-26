import { NativeModules, Platform } from 'react-native';

import type { MusicFile, MusicFolder } from '../types/music';

type MusicFolderModuleShape = {
  pickFolder(): Promise<MusicFolder>;
  listPlayableFiles(folderId: string, allowedExtensions: string[]): Promise<MusicFile[]>;
};

const LINKING_ERROR =
  `The native module 'MusicFolderModule' is unavailable on ${Platform.OS}. ` +
  'Rebuild the native app after installing dependencies and native changes.';

const NativeMusicFolderModule =
  NativeModules.MusicFolderModule as MusicFolderModuleShape | undefined;

function getModule(): MusicFolderModuleShape {
  if (!NativeMusicFolderModule) {
    throw new Error(LINKING_ERROR);
  }

  return NativeMusicFolderModule;
}

export const MusicFolderAccess = {
  pickFolder() {
    return getModule().pickFolder();
  },

  listPlayableFiles(folderId: string, allowedExtensions: string[]) {
    return getModule().listPlayableFiles(folderId, allowedExtensions);
  },
};