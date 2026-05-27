import { createContext, useContext, useEffect, useEffectEvent, useMemo, useRef, useState } from 'react';
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
import type { PlayerLoopMode, PlayerPlayMode, PlayerTrack, QueueTrack } from '../types/player';

type PlaylistTrackResolver = (track: QueueTrack) => Promise<PlayerTrack>;

type PlaylistSession = {
  completedRounds: number;
  currentTrackIndex: number;
  description?: string;
  loopMode: PlayerLoopMode;
  playMode: PlayerPlayMode;
  playlistId: string;
  playlistName: string;
  trackOrder: QueueTrack[];
  tracks: QueueTrack[];
};

type StartPlaylistPlaybackOptions = {
  description?: string;
  loopMode?: PlayerLoopMode;
  playMode: PlayerPlayMode;
  playlistId: string;
  playlistName: string;
  resolveTrack: PlaylistTrackResolver;
  tracks: QueueTrack[];
};

type PlayerContextValue = {
  canPlayNext: boolean;
  canPlayPrevious: boolean;
  currentLoopMode: PlayerLoopMode;
  currentPlayMode: PlayerPlayMode;
  currentPlaylistId: string | null;
  currentPlaylistName: string | null;
  closeExpanded: () => void;
  closeTrack: () => void;
  currentTrack: PlayerTrack | null;
  cycleLoopMode: () => void;
  duration: number;
  errorMessage: string | null;
  isBuffering: boolean;
  isExpanded: boolean;
  isPlaylistActive: boolean;
  isPlaying: boolean;
  openExpanded: () => void;
  playNextTrack: () => void;
  playPlaylist: (options: StartPlaylistPlaybackOptions) => Promise<void>;
  playPreviousTrack: () => void;
  playTrack: (track: PlayerTrack) => void;
  position: number;
  seekTo: (timeInSeconds: number) => void;
  togglePlayMode: () => void;
  togglePlayPause: () => void;
};

const PlayerContext = createContext<PlayerContextValue | null>(null);

function createShuffledOrder(tracks: QueueTrack[], currentTrackKey?: string) {
  const nextTracks = [...tracks];

  if (nextTracks.length <= 1) {
    return nextTracks;
  }

  const pinnedTrackIndex = currentTrackKey
    ? nextTracks.findIndex((track) => track.key === currentTrackKey)
    : -1;
  const pinnedTrack = pinnedTrackIndex >= 0 ? nextTracks.splice(pinnedTrackIndex, 1)[0] : null;

  for (let index = nextTracks.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1));
    [nextTracks[index], nextTracks[swapIndex]] = [nextTracks[swapIndex], nextTracks[index]];
  }

  return pinnedTrack ? [pinnedTrack, ...nextTracks] : nextTracks;
}

function createTrackOrder(
  tracks: QueueTrack[],
  playMode: PlayerPlayMode,
  currentTrackKey?: string,
) {
  return playMode === 'shuffle' ? createShuffledOrder(tracks, currentTrackKey) : [...tracks];
}

function cycleLoopModeValue(loopMode: PlayerLoopMode): PlayerLoopMode {
  switch (loopMode) {
    case 'once':
      return 'twice';
    case 'twice':
      return 'infinite';
    case 'infinite':
      return 'once';
  }
}

function buildAdvancedSession(
  session: PlaylistSession,
  direction: 'next' | 'previous',
): PlaylistSession | null {
  if (session.trackOrder.length === 0) {
    return null;
  }

  if (direction === 'previous') {
    if (session.currentTrackIndex > 0) {
      return {
        ...session,
        currentTrackIndex: session.currentTrackIndex - 1,
      };
    }

    return session;
  }

  const nextIndex = session.currentTrackIndex + 1;
  if (nextIndex < session.trackOrder.length) {
    return {
      ...session,
      currentTrackIndex: nextIndex,
    };
  }

  switch (session.loopMode) {
    case 'once':
      return null;
    case 'twice': {
      if (session.completedRounds >= 1) {
        return null;
      }

      return {
        ...session,
        completedRounds: session.completedRounds + 1,
        currentTrackIndex: 0,
        trackOrder: createTrackOrder(session.tracks, session.playMode),
      };
    }
    case 'infinite':
      return {
        ...session,
        completedRounds: session.completedRounds + 1,
        currentTrackIndex: 0,
        trackOrder: createTrackOrder(session.tracks, session.playMode),
      };
  }
}

export function PlayerProvider({ children }: Readonly<PropsWithChildren>) {
  const [currentTrack, setCurrentTrack] = useState<PlayerTrack | null>(null);
  const [playlistSession, setPlaylistSession] = useState<PlaylistSession | null>(null);
  const [isPaused, setIsPaused] = useState(true);
  const [isExpanded, setIsExpanded] = useState(false);
  const [isBuffering, setIsBuffering] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const playlistResolverRef = useRef<PlaylistTrackResolver | null>(null);
  const lastStatusRef = useRef<PlaybackStatus | null>(null);

  function updatePlaybackState(status: PlaybackStatus) {
    maybeAdvanceFinishedPlaylist(status);
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
  }

  function playResolvedTrack(track: PlayerTrack, preservePlaylist: boolean) {
    const isSameTrack = currentTrack?.key === track.key && currentTrack.url === track.url;
    setErrorMessage(null);
    setIsBuffering(true);

    if (!preservePlaylist) {
      playlistResolverRef.current = null;
      setPlaylistSession(null);
    }

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
        updatePlaybackState(status);
      })
      .catch((error) => {
        setIsPaused(true);
        setIsBuffering(false);
        setErrorMessage(error instanceof Error ? error.message : 'This track could not be played.');
      });
  }

  async function playPlaylistSessionTrack(session: PlaylistSession) {
    const queuedTrack = session.trackOrder[session.currentTrackIndex];
    const resolver = playlistResolverRef.current;

    if (!queuedTrack || !resolver) {
      throw new Error('Playlist playback is not available right now.');
    }

    const resolvedTrack = await resolver(queuedTrack);
    playResolvedTrack(
      {
        ...resolvedTrack,
        description:
          resolvedTrack.description ?? queuedTrack.description ?? session.description ?? session.playlistName,
      },
      true,
    );
  }

  async function advancePlaylist(direction: 'next' | 'previous') {
    if (!playlistSession) {
      return;
    }

    const nextSession = buildAdvancedSession(playlistSession, direction);

    if (!nextSession) {
      playlistResolverRef.current = null;
      setPlaylistSession(null);
      setCurrentTrack(null);
      setPosition(0);
      setDuration(0);
      setIsPaused(true);
      setIsBuffering(false);
      void stopPlayback().catch(() => {
        setErrorMessage('Playback could not be stopped.');
      });
      return;
    }

    setPlaylistSession(nextSession);

    try {
      await playPlaylistSessionTrack(nextSession);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Playlist playback could not continue.');
    }
  }

  function maybeAdvanceFinishedPlaylist(status: PlaybackStatus) {
    const previousStatus = lastStatusRef.current;
    lastStatusRef.current = status;

    if (!playlistSession || !previousStatus?.track || !status.track) {
      return;
    }

    const didFinishCurrentTrack =
      previousStatus.isPlaying &&
      !status.isPlaying &&
      !status.isBuffering &&
      !status.errorMessage &&
      previousStatus.track.key === status.track.key &&
      previousStatus.track.url === status.track.url &&
      status.position <= 0.25;

    if (didFinishCurrentTrack) {
      void advancePlaylist('next');
    }
  }

  const applyStatus = useEffectEvent((status: PlaybackStatus) => {
    updatePlaybackState(status);
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
    playResolvedTrack(track, false);
  }

  async function playPlaylist(options: StartPlaylistPlaybackOptions) {
    if (options.tracks.length === 0) {
      throw new Error('This playlist does not contain any playable tracks yet.');
    }

    const trackOrder = createTrackOrder(options.tracks, options.playMode);
    const session: PlaylistSession = {
      completedRounds: 0,
      currentTrackIndex: 0,
      description: options.description,
      loopMode: options.loopMode ?? 'once',
      playMode: options.playMode,
      playlistId: options.playlistId,
      playlistName: options.playlistName,
      trackOrder,
      tracks: options.tracks,
    };

    playlistResolverRef.current = options.resolveTrack;
    setPlaylistSession(session);
    setErrorMessage(null);
    await playPlaylistSessionTrack(session);
  }

  function playNextTrack() {
    void advancePlaylist('next');
  }

  function playPreviousTrack() {
    if (position > 3 && currentTrack) {
      seekTo(0);
      return;
    }

    void advancePlaylist('previous');
  }

  function togglePlayMode() {
    setPlaylistSession((currentSession) => {
      if (!currentSession) {
        return currentSession;
      }

      const nextPlayMode: PlayerPlayMode = currentSession.playMode === 'normal' ? 'shuffle' : 'normal';
      const currentQueuedTrack = currentSession.trackOrder[currentSession.currentTrackIndex];
      const nextTrackOrder = createTrackOrder(currentSession.tracks, nextPlayMode, currentQueuedTrack?.key);
      const nextTrackIndex = currentQueuedTrack
        ? nextTrackOrder.findIndex((track) => track.key === currentQueuedTrack.key)
        : 0;

      return {
        ...currentSession,
        currentTrackIndex: Math.max(nextTrackIndex, 0),
        playMode: nextPlayMode,
        trackOrder: nextTrackOrder,
      };
    });
  }

  function cycleLoopMode() {
    setPlaylistSession((currentSession) => {
      if (!currentSession) {
        return currentSession;
      }

      return {
        ...currentSession,
        loopMode: cycleLoopModeValue(currentSession.loopMode),
      };
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
    playlistResolverRef.current = null;
    setPlaylistSession(null);
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

  const value: PlayerContextValue = useMemo(
    () => ({
      canPlayNext: playlistSession !== null,
      canPlayPrevious: playlistSession !== null,
      closeExpanded: () => {
        setIsExpanded(false);
      },
      closeTrack,
      currentTrack,
      currentLoopMode: playlistSession?.loopMode ?? 'once',
      currentPlayMode: playlistSession?.playMode ?? 'normal',
      currentPlaylistId: playlistSession?.playlistId ?? null,
      currentPlaylistName: playlistSession?.playlistName ?? null,
      cycleLoopMode,
      duration,
      errorMessage,
      isBuffering,
      isExpanded,
      isPlaylistActive: playlistSession !== null,
      isPlaying: currentTrack !== null && !isPaused,
      openExpanded: () => {
        if (currentTrack) {
          setIsExpanded(true);
        }
      },
      playNextTrack,
      playPlaylist,
      playPreviousTrack,
      playTrack,
      position,
      seekTo,
      togglePlayMode,
      togglePlayPause,
    }),
    [
      closeTrack,
      currentTrack,
      cycleLoopMode,
      duration,
      errorMessage,
      isBuffering,
      isExpanded,
      isPaused,
      playNextTrack,
      playPlaylist,
      playPreviousTrack,
      playTrack,
      playlistSession,
      position,
      seekTo,
      togglePlayMode,
      togglePlayPause,
    ],
  );

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