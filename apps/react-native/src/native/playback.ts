import { NativeEventEmitter, NativeModules, Platform } from 'react-native';

import type { PlayerTrack } from '../types/player';

export type PlaybackStatus = {
  duration: number;
  errorMessage: string | null;
  hasTrack: boolean;
  isBuffering: boolean;
  isPlaying: boolean;
  position: number;
  track: PlayerTrack | null;
};

type PlaybackModuleType = {
  addListener: (eventName: string) => void;
  getStatus: () => Promise<PlaybackStatus>;
  load: (track: PlayerTrack) => Promise<PlaybackStatus>;
  pause: () => Promise<void>;
  play: () => Promise<void>;
  removeListeners: (count: number) => void;
  seekTo: (position: number) => Promise<void>;
  stop: () => Promise<void>;
};

const nativePlaybackModule =
  Platform.OS === 'android'
    ? (NativeModules.PlaybackModule as PlaybackModuleType | undefined)
    : undefined;

export const playbackEventName = 'PlaybackStatus';
export const playbackEventEmitter = nativePlaybackModule
  ? new NativeEventEmitter(nativePlaybackModule)
  : null;

export function isNativePlaybackAvailable() {
  return nativePlaybackModule != null;
}

export async function getPlaybackStatus() {
  if (!nativePlaybackModule) {
    throw new Error('Playback is only available on Android right now.');
  }

  return nativePlaybackModule.getStatus();
}

export async function loadPlaybackTrack(track: PlayerTrack) {
  if (!nativePlaybackModule) {
    throw new Error('Playback is only available on Android right now.');
  }

  return nativePlaybackModule.load(track);
}

export async function pausePlayback() {
  if (!nativePlaybackModule) {
    throw new Error('Playback is only available on Android right now.');
  }

  await nativePlaybackModule.pause();
}

export async function playPlayback() {
  if (!nativePlaybackModule) {
    throw new Error('Playback is only available on Android right now.');
  }

  await nativePlaybackModule.play();
}

export async function seekPlayback(position: number) {
  if (!nativePlaybackModule) {
    throw new Error('Playback is only available on Android right now.');
  }

  await nativePlaybackModule.seekTo(position);
}

export async function stopPlayback() {
  if (!nativePlaybackModule) {
    throw new Error('Playback is only available on Android right now.');
  }

  await nativePlaybackModule.stop();
}