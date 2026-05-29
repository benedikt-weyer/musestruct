import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { usePlayer } from '../context/PlayerContext';
import { useSettings } from '../context/SettingsContext';
import { fetchLastPlayedTracks } from '../services/libraryApi';
import { fetchStreamingTrack, fetchTrackStreamUrl } from '../services/streamingLibraryApi';
import type { LastPlayedTrack } from '../types/library';

function formatDuration(duration?: number | null) {
  if (!duration || duration <= 0) {
    return '--:--';
  }

  const minutes = Math.floor(duration / 60);
  const seconds = duration % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

function formatDate(value?: string | null) {
  if (!value) {
    return 'Unknown date';
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleDateString();
}

function LastPlayedTrackCard({
  isDarkMode,
  isCurrentTrack,
  isPlaying,
  onPlay,
  track,
}: Readonly<{
  isDarkMode: boolean;
  isCurrentTrack: boolean;
  isPlaying: boolean;
  onPlay: (track: LastPlayedTrack) => void;
  track: LastPlayedTrack;
}>) {
  let playLabel = 'Play track';
  if (isCurrentTrack && isPlaying) {
    playLabel = 'Pause track';
  } else if (isCurrentTrack) {
    playLabel = 'Resume track';
  }

  return (
    <View style={[styles.trackCard, isDarkMode && styles.cardDark]}>
      <View style={styles.trackRow}>
        {track.cover_url ? (
          <Image
            resizeMode="cover"
            source={{ uri: track.cover_url }}
            style={[styles.coverImage, isDarkMode && styles.coverImageDark]}
          />
        ) : (
          <View style={[styles.coverFallback, isDarkMode && styles.coverFallbackDark]}>
            <Text style={[styles.sourceText, isDarkMode && styles.sourceTextDark]}>
              {track.source}
            </Text>
          </View>
        )}

        <View style={styles.trackInfo}>
          <Text style={[styles.trackTitle, isDarkMode && styles.trackTitleDark]}>{track.title}</Text>
          <Text style={[styles.trackArtist, isDarkMode && styles.trackArtistDark]}>{track.artist}</Text>
          <Text style={[styles.trackAlbum, isDarkMode && styles.trackAlbumDark]}>{track.album}</Text>
          <View style={styles.trackMetaRow}>
            <Text style={[styles.trackMetaText, isDarkMode && styles.trackMetaTextDark]}>
              {track.source}
            </Text>
            <Text style={[styles.trackMetaText, isDarkMode && styles.trackMetaTextDark]}>
              {formatDuration(track.duration)}
            </Text>
          </View>
          <Text style={[styles.playedAtText, isDarkMode && styles.playedAtTextDark]}>
            Played {formatDate(track.played_at)}
          </Text>
        </View>
      </View>

      <Pressable
        accessibilityRole="button"
        onPress={() => {
          onPlay(track);
        }}
        style={({ pressed }) => [
          styles.trackActionButton,
          isDarkMode && styles.trackActionButtonDark,
          pressed && (isDarkMode ? styles.trackActionButtonPressedDark : styles.trackActionButtonPressed),
        ]}
      >
        <Text style={[styles.trackActionText, isDarkMode && styles.trackActionTextDark]}>{playLabel}</Text>
      </Pressable>
    </View>
  );
}

export function HomeScreen() {
  const { authSession, backendUrl, themePreference } = useSettings();
  const { currentTrack, isPlaying, playTrack, togglePlayPause } = usePlayer();
  const [tracks, setTracks] = useState<LastPlayedTrack[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const isDarkMode = themePreference === 'dark';

  async function loadRecentTracks() {
    if (!authSession) {
      setTracks([]);
      setErrorMessage(null);
      return;
    }

    setIsLoading(true);
    setErrorMessage(null);

    try {
      const response = await fetchLastPlayedTracks(backendUrl, authSession, 20);
      setTracks(response.tracks);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Recent tracks could not be loaded.');
      setTracks([]);
    } finally {
      setIsLoading(false);
    }
  }

  async function handlePlayTrack(track: LastPlayedTrack) {
    const playerKey = `${track.source}:${track.track_id}`;
    if (currentTrack?.key === playerKey) {
      togglePlayPause();
      return;
    }

    if (!authSession) {
      return;
    }

    if (track.source === 'spotify') {
      setErrorMessage('Spotify playback from recent tracks is only available for tracks with a preview clip.');
      return;
    }

    try {
      const playbackTrack =
        track.source === 'tidal'
          ? await fetchStreamingTrack(backendUrl, authSession, track.track_id, track.source)
          : null;

      playTrack({
        id: track.track_id,
        key: playerKey,
        userTrackId: track.id,
        title: playbackTrack?.title ?? track.title,
        artist: playbackTrack?.artist ?? track.artist,
        album: playbackTrack?.album ?? track.album,
        artworkUrl: playbackTrack?.cover_url ?? track.cover_url,
        duration: playbackTrack?.duration ?? track.duration ?? undefined,
        source: track.source,
        url:
          track.source === 'tidal'
            ? ''
            : await fetchTrackStreamUrl(backendUrl, authSession, track.track_id, track.source),
        backendUrl: track.source === 'tidal' ? backendUrl : undefined,
        sessionToken: track.source === 'tidal' ? authSession.sessionToken : undefined,
      });
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to play recent track.');
    }
  }

  useEffect(() => {
    void loadRecentTracks();
  }, [authSession, backendUrl]);

  return (
    <SafeAreaView style={[styles.safeArea, isDarkMode && styles.safeAreaDark]} edges={['left', 'right']}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent}>
        <View style={[styles.heroCard, isDarkMode && styles.cardDark]}>
          <Text style={[styles.heroEyebrow, isDarkMode && styles.heroEyebrowDark]}>
            Home
          </Text>
          <Text style={[styles.heroTitle, isDarkMode && styles.heroTitleDark]}>Recently Played</Text>
          <Text style={[styles.heroDescription, isDarkMode && styles.heroDescriptionDark]}>
            Resume the saved user-library tracks you played most recently.
          </Text>
        </View>

        {errorMessage ? (
          <View style={styles.errorCard}>
            <Text style={styles.errorTitle}>Recent tracks failed to load</Text>
            <Text style={styles.errorMessage}>{errorMessage}</Text>
          </View>
        ) : null}

        <View style={[styles.refreshCard, isDarkMode && styles.cardDark]}>
          <Pressable
            accessibilityRole="button"
            disabled={isLoading}
            onPress={() => {
              void loadRecentTracks();
            }}
            style={({ pressed }) => [
              styles.refreshButton,
              isDarkMode && styles.refreshButtonDark,
              pressed && (isDarkMode ? styles.refreshButtonPressedDark : styles.refreshButtonPressed),
              isLoading && styles.disabledButton,
            ]}
          >
            <Text style={[styles.refreshButtonText, isDarkMode && styles.refreshButtonTextDark]}>
              Refresh recent tracks
            </Text>
          </Pressable>
        </View>

        {!authSession ? (
          <View style={[styles.emptyStateCard, isDarkMode && styles.emptyStateCardDark]}>
            <Text style={[styles.emptyStateTitle, isDarkMode && styles.emptyStateTitleDark]}>Login required</Text>
            <Text style={[styles.emptyStateDescription, isDarkMode && styles.emptyStateDescriptionDark]}>
              Recently played history is tracked for saved backend user tracks, so sign in to see it here.
            </Text>
          </View>
        ) : isLoading ? (
          <View style={[styles.loadingCard, isDarkMode && styles.cardDark]}>
            <ActivityIndicator color="#0f766e" />
          </View>
        ) : tracks.length === 0 ? (
          <View style={[styles.emptyStateCard, isDarkMode && styles.emptyStateCardDark]}>
            <Text style={[styles.emptyStateTitle, isDarkMode && styles.emptyStateTitleDark]}>No recent tracks yet</Text>
            <Text style={[styles.emptyStateDescription, isDarkMode && styles.emptyStateDescriptionDark]}>
              Start playback from your saved tracks or playlists and those user tracks will appear here.
            </Text>
          </View>
        ) : (
          <View style={styles.trackList}>
            {tracks.map((track) => (
              <LastPlayedTrackCard
                isDarkMode={isDarkMode}
                isCurrentTrack={currentTrack?.key === `${track.source}:${track.track_id}`}
                isPlaying={isPlaying}
                key={track.id}
                onPlay={(selectedTrack) => {
                  void handlePlayTrack(selectedTrack);
                }}
                track={track}
              />
            ))}
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: '#f8fafc',
  },
  safeAreaDark: {
    backgroundColor: '#020617',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 24,
  },
  cardDark: {
    backgroundColor: '#0f172a',
    shadowOpacity: 0,
    elevation: 0,
  },
  heroCard: {
    borderRadius: 28,
    backgroundColor: '#ffffff',
    paddingHorizontal: 20,
    paddingVertical: 20,
    shadowColor: '#cbd5e1',
    shadowOpacity: 0.35,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  },
  heroEyebrow: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 2,
    textTransform: 'uppercase',
    color: '#64748b',
  },
  heroEyebrowDark: {
    color: '#94a3b8',
  },
  heroTitle: {
    marginTop: 8,
    fontSize: 30,
    fontWeight: '700',
    color: '#0f172a',
  },
  heroTitleDark: {
    color: '#f1f5f9',
  },
  heroDescription: {
    marginTop: 12,
    fontSize: 14,
    lineHeight: 24,
    color: '#475569',
  },
  heroDescriptionDark: {
    color: '#94a3b8',
  },
  errorCard: {
    marginTop: 16,
    borderRadius: 24,
    borderWidth: 1,
    borderColor: '#fecdd3',
    backgroundColor: '#fff1f2',
    paddingHorizontal: 16,
    paddingVertical: 16,
  },
  errorTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#881337',
  },
  errorMessage: {
    marginTop: 4,
    fontSize: 14,
    color: '#be123c',
  },
  refreshCard: {
    marginTop: 16,
    borderRadius: 24,
    backgroundColor: '#ffffff',
    paddingHorizontal: 16,
    paddingVertical: 16,
    shadowColor: '#cbd5e1',
    shadowOpacity: 0.35,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  },
  refreshButton: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    backgroundColor: '#ffffff',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  refreshButtonDark: {
    borderColor: '#334155',
    backgroundColor: '#020617',
  },
  refreshButtonPressed: {
    backgroundColor: '#f1f5f9',
  },
  refreshButtonPressedDark: {
    backgroundColor: '#1e293b',
  },
  disabledButton: {
    opacity: 0.6,
  },
  refreshButtonText: {
    textAlign: 'center',
    fontSize: 14,
    fontWeight: '600',
    color: '#334155',
  },
  refreshButtonTextDark: {
    color: '#e2e8f0',
  },
  emptyStateCard: {
    marginTop: 16,
    borderRadius: 24,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: '#cbd5e1',
    backgroundColor: '#ffffff',
    paddingHorizontal: 16,
    paddingVertical: 24,
  },
  emptyStateCardDark: {
    borderColor: '#334155',
    backgroundColor: '#0f172a',
  },
  emptyStateTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#0f172a',
  },
  emptyStateTitleDark: {
    color: '#f1f5f9',
  },
  emptyStateDescription: {
    marginTop: 8,
    fontSize: 14,
    lineHeight: 24,
    color: '#475569',
  },
  emptyStateDescriptionDark: {
    color: '#94a3b8',
  },
  loadingCard: {
    marginTop: 16,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 24,
    backgroundColor: '#ffffff',
    paddingHorizontal: 20,
    paddingVertical: 40,
    shadowColor: '#cbd5e1',
    shadowOpacity: 0.35,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  },
  trackList: {
    marginTop: 16,
  },
  trackCard: {
    marginBottom: 12,
    borderRadius: 24,
    backgroundColor: '#ffffff',
    paddingHorizontal: 16,
    paddingVertical: 16,
    shadowColor: '#cbd5e1',
    shadowOpacity: 0.35,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 2,
  },
  trackRow: {
    flexDirection: 'row',
    columnGap: 16,
  },
  coverImage: {
    height: 64,
    width: 64,
    borderRadius: 18,
    backgroundColor: '#f1f5f9',
  },
  coverImageDark: {
    backgroundColor: '#1e293b',
  },
  coverFallback: {
    height: 64,
    width: 64,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 18,
    backgroundColor: '#f1f5f9',
  },
  coverFallbackDark: {
    backgroundColor: '#1e293b',
  },
  sourceText: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
    color: '#64748b',
  },
  sourceTextDark: {
    color: '#94a3b8',
  },
  trackInfo: {
    flex: 1,
  },
  trackTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#0f172a',
  },
  trackTitleDark: {
    color: '#f1f5f9',
  },
  trackArtist: {
    marginTop: 4,
    fontSize: 14,
    color: '#475569',
  },
  trackArtistDark: {
    color: '#cbd5e1',
  },
  trackAlbum: {
    marginTop: 4,
    fontSize: 14,
    color: '#64748b',
  },
  trackAlbumDark: {
    color: '#94a3b8',
  },
  trackMetaRow: {
    marginTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  trackMetaText: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
    color: '#94a3b8',
  },
  trackMetaTextDark: {
    color: '#64748b',
  },
  playedAtText: {
    marginTop: 8,
    fontSize: 12,
    color: '#94a3b8',
  },
  playedAtTextDark: {
    color: '#64748b',
  },
  trackActionButton: {
    marginTop: 16,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#e2e8f0',
    backgroundColor: '#ffffff',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  trackActionButtonDark: {
    borderColor: '#334155',
    backgroundColor: '#020617',
  },
  trackActionButtonPressed: {
    backgroundColor: '#f1f5f9',
  },
  trackActionButtonPressedDark: {
    backgroundColor: '#1e293b',
  },
  trackActionText: {
    textAlign: 'center',
    fontSize: 14,
    fontWeight: '600',
    color: '#334155',
  },
  trackActionTextDark: {
    color: '#e2e8f0',
  },
});