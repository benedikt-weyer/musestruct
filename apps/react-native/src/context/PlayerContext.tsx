import { createContext, useContext, useRef, useState } from 'react';
import type { PropsWithChildren } from 'react';
import Video, {
  type OnBufferData,
  type OnLoadData,
  type OnProgressData,
  type VideoRef,
} from 'react-native-video';

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
  const playerRef = useRef<VideoRef | null>(null);
  const [currentTrack, setCurrentTrack] = useState<PlayerTrack | null>(null);
  const [isPaused, setIsPaused] = useState(true);
  const [isExpanded, setIsExpanded] = useState(false);
  const [isBuffering, setIsBuffering] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  function playTrack(track: PlayerTrack) {
    const isSameTrack = currentTrack?.key === track.key && currentTrack.url === track.url;
    setErrorMessage(null);
    setIsBuffering(true);

    if (isSameTrack) {
      setIsPaused(false);
      return;
    }

    setCurrentTrack(track);
    setPosition(0);
    setDuration(track.duration ?? 0);
    setIsPaused(false);
    setIsExpanded(false);
  }

  function togglePlayPause() {
    if (!currentTrack) {
      return;
    }

    setIsPaused((value) => !value);
  }

  function seekTo(timeInSeconds: number) {
    if (!currentTrack) {
      return;
    }

    playerRef.current?.seek(timeInSeconds);
    setPosition(timeInSeconds);
  }

  function closeTrack() {
    setIsPaused(true);
    setIsExpanded(false);
    setCurrentTrack(null);
    setPosition(0);
    setDuration(0);
    setIsBuffering(false);
    setErrorMessage(null);
  }

  function handleLoad(event: OnLoadData) {
    setDuration(event.duration || currentTrack?.duration || 0);
    setPosition(event.currentTime || 0);
    setIsBuffering(false);
    setErrorMessage(null);
  }

  function handleProgress(event: OnProgressData) {
    setPosition(event.currentTime);
  }

  function handleBuffer(event: OnBufferData) {
    setIsBuffering(event.isBuffering);
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
      {currentTrack ? (
        <Video
          ignoreSilentSwitch="ignore"
          onBuffer={handleBuffer}
          onEnd={() => {
            setIsPaused(true);
            setPosition(0);
            setIsBuffering(false);
          }}
          onError={() => {
            setIsPaused(true);
            setIsBuffering(false);
            setErrorMessage('This track could not be played.');
          }}
          onLoad={handleLoad}
          onProgress={handleProgress}
          paused={isPaused}
          playInBackground={false}
          playWhenInactive={false}
          progressUpdateInterval={500}
          ref={playerRef}
          source={{ uri: currentTrack.url }}
          style={{ height: 0, width: 0 }}
        />
      ) : null}
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