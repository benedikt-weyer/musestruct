import { useEffect, useMemo, useState } from 'react';
import { useNavigation, useRoute } from '@react-navigation/native';
import type { RouteProp } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
  ActivityIndicator,
  Image,
  Pressable,
  ScrollView,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { usePlayer } from '../context/PlayerContext';
import { useSettings } from '../context/SettingsContext';
import type { RootStackParamList } from '../navigation/types';
import { fetchLibraryPlaylistItems } from '../services/libraryApi';
import { fetchStreamingTrack, fetchTrackStreamUrl } from '../services/streamingLibraryApi';
import type { LibraryPlaylistItem } from '../types/library';

function formatDuration(duration?: number | null) {
  if (!duration || duration <= 0) {
    return '--:--';
  }

  const minutes = Math.floor(duration / 60);
  const seconds = duration % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

function formatDate(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleDateString();
}

function EmptyPlaylistState({
  description,
  title,
}: Readonly<{
  description: string;
  title: string;
}>) {
  return (
    <View className="rounded-[24px] border border-dashed border-slate-300 bg-white px-5 py-8 dark:border-slate-700 dark:bg-slate-900">
      <Text className="text-lg font-semibold text-slate-900 dark:text-slate-100">{title}</Text>
      <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">{description}</Text>
    </View>
  );
}

function SubPlaylistCard({
  item,
  onOpen,
}: Readonly<{
  item: LibraryPlaylistItem;
  onOpen: (item: LibraryPlaylistItem) => void;
}>) {
  return (
    <Pressable
      accessibilityRole="button"
      className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 active:bg-slate-50 dark:bg-slate-900 dark:shadow-none dark:active:bg-slate-800"
      onPress={() => {
        onOpen(item);
      }}
    >
      <View className="flex-row items-start justify-between gap-4">
        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">
            {item.playlist_name ?? item.title ?? 'Untitled playlist'}
          </Text>
          <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
            Open this nested playlist to inspect its tracks and sub playlists.
          </Text>
          <Text className="mt-3 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
            Nested playlist • Added {formatDate(item.added_at)}
          </Text>
        </View>
        <View className="rounded-full bg-slate-100 px-3 py-2 dark:bg-slate-800">
          <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-600 dark:text-slate-300">
            Open
          </Text>
        </View>
      </View>
    </Pressable>
  );
}

function PlaylistTrackCard({
  isBuffering,
  isCurrentTrack,
  isPlaying,
  item,
  onPlay,
}: Readonly<{
  isBuffering: boolean;
  isCurrentTrack: boolean;
  isPlaying: boolean;
  item: LibraryPlaylistItem;
  onPlay: (item: LibraryPlaylistItem) => void;
}>) {
  let playLabel = 'Play track';
  if (isCurrentTrack && isPlaying) {
    playLabel = 'Pause track';
  } else if (isCurrentTrack) {
    playLabel = 'Resume track';
  } else if (isBuffering) {
    playLabel = 'Loading...';
  }

  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <View className="flex-row gap-4">
        {item.cover_url ? (
          <Image
            className="h-16 w-16 rounded-[18px] bg-slate-100 dark:bg-slate-800"
            resizeMode="cover"
            source={{ uri: item.cover_url }}
          />
        ) : (
          <View className="h-16 w-16 items-center justify-center rounded-[18px] bg-slate-100 dark:bg-slate-800">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400">
              {item.source ?? 'track'}
            </Text>
          </View>
        )}

        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">
            {item.title ?? 'Unknown Track'}
          </Text>
          <Text className="mt-1 text-sm text-slate-600 dark:text-slate-300">
            {item.artist ?? 'Unknown Artist'}
          </Text>
          <Text className="mt-1 text-sm text-slate-500 dark:text-slate-400">
            {item.album ?? 'Unknown Album'}
          </Text>
          <View className="mt-3 flex-row items-center justify-between">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              {item.source ?? 'unknown'}
            </Text>
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              {formatDuration(item.duration)}
            </Text>
          </View>
        </View>
      </View>

      <Pressable
        accessibilityRole="button"
        className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
        onPress={() => {
          onPlay(item);
        }}
      >
        <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
          {playLabel}
        </Text>
      </Pressable>
    </View>
  );
}

export function PlaylistDetailsScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const route = useRoute<RouteProp<RootStackParamList, 'PlaylistDetails'>>();
  const { authSession, backendUrl } = useSettings();
  const { currentTrack, isBuffering, isPlaying, playTrack, togglePlayPause } = usePlayer();
  const [items, setItems] = useState<LibraryPlaylistItem[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const { playlistDescription, playlistId, playlistName } = route.params;
  const trackItems = useMemo(() => items.filter((item) => !item.is_playlist), [items]);
  const subPlaylistItems = useMemo(() => items.filter((item) => item.is_playlist), [items]);
  const currentTrackKey = currentTrack?.key ?? null;

  useEffect(() => {
    if (!authSession) {
      setItems([]);
      setErrorMessage(null);
      return;
    }

    let cancelled = false;

    void (async () => {
      setIsLoading(true);
      setErrorMessage(null);

      try {
        const nextItems = await fetchLibraryPlaylistItems(backendUrl, authSession, playlistId);
        if (!cancelled) {
          setItems(nextItems);
        }
      } catch (error) {
        if (!cancelled) {
          setErrorMessage(
            error instanceof Error ? error.message : 'Failed to load playlist items.',
          );
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [authSession, backendUrl, playlistId]);

  async function handlePlayTrack(item: LibraryPlaylistItem) {
    if (!authSession || !item.source) {
      return;
    }

    const playerKey = `${item.source}:${item.item_id}`;
    if (currentTrack?.key === playerKey) {
      togglePlayPause();
      return;
    }

    if (item.source === 'spotify') {
      setErrorMessage('Spotify playback is only available for tracks with a preview clip.');
      return;
    }

    try {
      const playbackTrack =
        item.source === 'tidal'
          ? await fetchStreamingTrack(backendUrl, authSession, item.item_id, item.source)
          : null;

      playTrack({
        album: playbackTrack?.album ?? item.album ?? 'Unknown Album',
        artist: playbackTrack?.artist ?? item.artist ?? 'Unknown Artist',
        artworkUrl: playbackTrack?.cover_url ?? item.cover_url,
        backendUrl: item.source === 'tidal' ? backendUrl : undefined,
        duration: playbackTrack?.duration ?? item.duration ?? undefined,
        id: item.item_id,
        key: playerKey,
        sessionToken: item.source === 'tidal' ? authSession.sessionToken : undefined,
        source: item.source,
        title: playbackTrack?.title ?? item.title ?? 'Unknown Track',
        url:
          item.source === 'tidal'
            ? ''
            : await fetchTrackStreamUrl(backendUrl, authSession, item.item_id, item.source),
      });
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to play track.');
    }
  }

  function handleOpenSubPlaylist(item: LibraryPlaylistItem) {
    navigation.push('PlaylistDetails', {
      playlistDescription: null,
      playlistId: item.item_id,
      playlistName: item.playlist_name ?? item.title ?? 'Playlist',
    });
  }

  return (
    <SafeAreaView className="flex-1 bg-slate-50 dark:bg-slate-950" edges={['left', 'right']}>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, paddingTop: 16 }}
      >
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-2xl font-bold text-slate-900 dark:text-slate-100">
            {playlistName}
          </Text>
          <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
            {playlistDescription ?? 'Browse the tracks and nested playlists in this collection.'}
          </Text>
          <Text className="mt-4 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
            {trackItems.length} tracks • {subPlaylistItems.length} playlists
          </Text>
        </View>

        {errorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm font-semibold text-rose-700">{errorMessage}</Text>
          </View>
        ) : null}

        {isLoading ? (
          <View className="mt-6 flex-row items-center justify-center rounded-[24px] bg-white px-4 py-8 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
            <ActivityIndicator color="#0f766e" />
            <Text className="ml-3 text-sm font-medium text-slate-600 dark:text-slate-300">
              Loading playlist items...
            </Text>
          </View>
        ) : null}

        {!isLoading && subPlaylistItems.length > 0 ? (
          <View className="mt-6">
            <Text className="mb-3 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              Nested playlists
            </Text>
            {subPlaylistItems.map((item) => (
              <SubPlaylistCard item={item} key={item.id} onOpen={handleOpenSubPlaylist} />
            ))}
          </View>
        ) : null}

        {!isLoading && trackItems.length > 0 ? (
          <View className="mt-6">
            <Text className="mb-3 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              Tracks
            </Text>
            {trackItems.map((item) => (
              <PlaylistTrackCard
                isBuffering={isBuffering}
                isCurrentTrack={currentTrackKey === `${item.source}:${item.item_id}`}
                isPlaying={isPlaying}
                item={item}
                key={item.id}
                onPlay={handlePlayTrack}
              />
            ))}
          </View>
        ) : null}

        {!isLoading && items.length === 0 ? (
          <View className="mt-6">
            <EmptyPlaylistState
              description="This playlist does not contain any tracks or nested playlists yet."
              title="No items yet"
            />
          </View>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}