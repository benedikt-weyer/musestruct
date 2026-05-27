import { createContext, useContext, useEffect, useEffectEvent, useState } from 'react';
import type { PropsWithChildren } from 'react';

import {
  getPlaybackStatus,
  isNativePlaybackAvailable,
  loadPlaybackTrack,
  pausePlayback,
  playbackEventEmitter,
  playbackEventName,
  playPlayback,
  seekPlayback,
  stopPlayback,
  type PlaybackStatus,
} from '../native/playback';
import type { PlayerTrack } from '../types/player';

type PlayerContextValue = {
  closeExpanded: () => void;
  closeTrack: () => void;
  currentTrack: PlayerTrack | null;
  duration: number;
  errorMessage: string | null;
  isBuffering: boolean;
  isExpanded: boolean;
  isPlaying: boolean;
  openExpanded: () => void;
  playTrack: (track: PlayerTrack) => void;
  position: number;
  seekTo: (timeInSeconds: number) => void;
  togglePlayPause: () => void;
};

const PlayerContext = createContext<PlayerContextValue | null>(null);

export function PlayerProvider({ children }: Readonly<PropsWithChildren>) {
  const [currentTrack, setCurrentTrack] = useState<PlayerTrack | null>(null);
  const [isPaused, setIsPaused] = useState(true);
  const [isExpanded, setIsExpanded] = useState(false);
  const [isBuffering, setIsBuffering] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const applyStatus = useEffectEvent((status: PlaybackStatus) => {
    setIsBuffering(status.isBuffering);
    setIsPaused(!status.isPlaying);
    setPosition(status.position);
    setDuration(status.duration);
    setErrorMessage(status.errorMessage);

    if (status.track) {
      setCurrentTrack(status.track);
      return;
    }

    setCurrentTrack(null);
    setIsExpanded(false);
    setPosition(0);
    setDuration(0);
  });

  const syncStatus = useEffectEvent(async () => {
    if (!isNativePlaybackAvailable()) {
      return;
    }

    try {
      applyStatus(await getPlaybackStatus());
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : 'Playback status could not be loaded.',
      );
    }
  });

  useEffect(() => {
    if (!isNativePlaybackAvailable() || !playbackEventEmitter) {
      return;
    }

    const subscription = playbackEventEmitter.addListener(playbackEventName, (status) => {
      applyStatus(status as PlaybackStatus);
    });

    void syncStatus();

    return () => {
      subscription.remove();
    };
  }, []);

  function playTrack(track: PlayerTrack) {
    const isSameTrack = currentTrack?.key === track.key && currentTrack.url === track.url;
    setErrorMessage(null);
    setIsBuffering(true);

    if (!isNativePlaybackAvailable()) {
      setIsBuffering(false);
      setErrorMessage('Playback is only available on Android right now.');
      return;
    }

    if (isSameTrack) {
      setCurrentTrack(track);
      setIsPaused(false);
      void playPlayback().catch((error) => {
        setIsPaused(true);
        setIsBuffering(false);
        setErrorMessage(error instanceof Error ? error.message : 'Playback could not resume.');
      });
      return;
    }

    setCurrentTrack(track);
    setPosition(0);
    setDuration(track.duration ?? 0);
    setIsPaused(false);
    setIsExpanded(false);

    void loadPlaybackTrack(track)
      .then((status) => {
        applyStatus(status);
      })
      .catch((error) => {
        setIsPaused(true);
        setIsBuffering(false);
        setErrorMessage(error instanceof Error ? error.message : 'This track could not be played.');
      });
  }

  function togglePlayPause() {
    if (!currentTrack) {
      return;
    }

    if (!isNativePlaybackAvailable()) {
      setErrorMessage('Playback is only available on Android right now.');
      return;
    }

    const shouldPause = !isPaused;
    setIsPaused(shouldPause);

    void (shouldPause ? pausePlayback() : playPlayback()).catch((error) => {
      setIsPaused(!shouldPause);
      setErrorMessage(
        error instanceof Error ? error.message : 'Playback state could not be updated.',
      );
    });
  }

  function seekTo(timeInSeconds: number) {
    if (!currentTrack) {
      return;
    }

    setPosition(timeInSeconds);

    if (!isNativePlaybackAvailable()) {
      setErrorMessage('Playback is only available on Android right now.');
      return;
    }

    void seekPlayback(timeInSeconds).catch((error) => {
      setErrorMessage(error instanceof Error ? error.message : 'Playback could not seek.');
    });
  }

  function closeTrack() {
    setIsPaused(true);
    setIsExpanded(false);
    setCurrentTrack(null);
    setPosition(0);
    setDuration(0);
    setIsBuffering(false);
    setErrorMessage(null);

    if (!isNativePlaybackAvailable()) {
      return;
    }

    void stopPlayback().catch(() => {
      setErrorMessage('Playback could not be stopped.');
    });
  }

  const value: PlayerContextValue = {
    closeExpanded: () => {
      setIsExpanded(false);
    },
    closeTrack,
    currentTrack,
    duration,
    errorMessage,
    isBuffering,
    isExpanded,
    isPlaying: currentTrack !== null && !isPaused,
    openExpanded: () => {
      if (currentTrack) {
        setIsExpanded(true);
      }
    },
    playTrack,
    position,
    seekTo,
    togglePlayPause,
  };

  return (
    <PlayerContext.Provider value={value}>
      {children}
    </PlayerContext.Provider>
  );
}

export function usePlayer() {
  const context = useContext(PlayerContext);

  if (!context) {
    throw new Error('usePlayer must be used inside PlayerProvider.');
  }

  return context;
}