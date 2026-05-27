import { useEffect, useMemo, useState } from 'react';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
  ActivityIndicator,
  Alert,
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
import {
  deleteLibraryPlaylist,
  deleteSavedAlbum,
  deleteSavedTrack,
  fetchLibraryPlaylistItems,
  fetchLibraryPlaylists,
  fetchSavedAlbums,
  fetchSavedTracks,
} from '../services/libraryApi';
import { fetchTrackStreamUrl } from '../services/streamingLibraryApi';
import type {
  LibraryPlaylist,
  LibraryPlaylistItem,
  LibrarySection,
  SavedAlbum,
  SavedTrack,
} from '../types/library';
import type { PlayerPlayMode, QueueTrack } from '../types/player';

type LibrarySectionOption = {
  key: LibrarySection;
  label: string;
  subtitle: string;
};

const LIBRARY_SECTIONS: LibrarySectionOption[] = [
  {
    key: 'playlists',
    label: 'Playlists',
    subtitle: 'Your playlists stored in the Musestruct backend.',
  },
  {
    key: 'albums',
    label: 'Albums',
    subtitle: 'Albums you already added to your personal library.',
  },
  {
    key: 'tracks',
    label: 'Tracks',
    subtitle: 'Every track currently saved in your library.',
  },
  {
    key: 'favourites',
    label: 'Favourites',
    subtitle: 'Saved tracks are treated as favourites in the current backend model.',
  },
];

function formatDuration(duration: number) {
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

function getTrackPlayLabel(isCurrentTrack: boolean, isPlaying: boolean) {
  if (isCurrentTrack && isPlaying) {
    return 'Pause track';
  }

  if (isCurrentTrack) {
    return 'Resume track';
  }

  return 'Play track';
}

function LibrarySectionButton({
  active,
  count,
  label,
  onPress,
}: Readonly<{
  active: boolean;
  count: number;
  label: string;
  onPress: () => void;
}>) {
  const containerClassName = active
    ? 'mr-3 rounded-full bg-slate-900 px-4 py-3 dark:bg-teal-700'
    : 'mr-3 rounded-full border border-slate-200 bg-white px-4 py-3 dark:border-slate-700 dark:bg-slate-900';
  const labelClassName = active
    ? 'text-sm font-semibold text-white'
    : 'text-sm font-semibold text-slate-700 dark:text-slate-200';
  const countClassName = active
    ? 'mt-1 text-xs font-semibold uppercase tracking-[1px] text-slate-300'
    : 'mt-1 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500';

  return (
    <Pressable accessibilityRole="button" className={containerClassName} onPress={onPress}>
      <Text className={labelClassName}>{label}</Text>
      <Text className={countClassName}>{count} items</Text>
    </Pressable>
  );
}

function EmptyLibraryState({
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

function TrackLibraryCard({
  isRemoving,
  isCurrentTrack,
  isPlaying,
  onPlay,
  onRemove,
  showFavouriteBadge,
  track,
}: Readonly<{
  isRemoving: boolean;
  isCurrentTrack: boolean;
  isPlaying: boolean;
  onPlay: (track: SavedTrack) => void;
  onRemove: (track: SavedTrack) => void;
  showFavouriteBadge: boolean;
  track: SavedTrack;
}>) {
  const playLabel = getTrackPlayLabel(isCurrentTrack, isPlaying);

  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <View className="flex-row gap-4">
        {track.cover_url ? (
          <Image
            className="h-16 w-16 rounded-[18px] bg-slate-100 dark:bg-slate-800"
            resizeMode="cover"
            source={{ uri: track.cover_url }}
          />
        ) : (
          <View className="h-16 w-16 items-center justify-center rounded-[18px] bg-slate-100 dark:bg-slate-800">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400">
              {track.source}
            </Text>
          </View>
        )}

        <View className="flex-1">
          <View className="flex-row items-start justify-between gap-3">
            <Text className="flex-1 text-base font-semibold text-slate-900 dark:text-slate-100">{track.title}</Text>
            {showFavouriteBadge ? (
              <View className="rounded-full bg-rose-100 px-3 py-1">
                <Text className="text-xs font-semibold uppercase tracking-[1px] text-rose-700">
                  Favourite
                </Text>
              </View>
            ) : null}
          </View>
          <Text className="mt-1 text-sm text-slate-600 dark:text-slate-300">{track.artist}</Text>
          <Text className="mt-1 text-sm text-slate-500 dark:text-slate-400">{track.album}</Text>
          <View className="mt-3 flex-row items-center justify-between">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              {track.source}
            </Text>
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              {formatDuration(track.duration)}
            </Text>
          </View>
          <Text className="mt-2 text-xs text-slate-400 dark:text-slate-500">Saved {formatDate(track.created_at)}</Text>
        </View>
      </View>

      <View className="mt-4 flex-row gap-3">
        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
          onPress={() => {
            onPlay(track);
          }}
        >
          <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
            {playLabel}
          </Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="rounded-full border border-rose-200 bg-rose-50 px-4 py-3 active:bg-rose-100"
          disabled={isRemoving}
          onPress={() => {
            onRemove(track);
          }}
        >
          <Text className="text-center text-sm font-semibold text-rose-700">
            {isRemoving ? 'Removing...' : 'Remove'}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

function AlbumLibraryCard({
  album,
  isRemoving,
  onRemove,
}: Readonly<{
  album: SavedAlbum;
  isRemoving: boolean;
  onRemove: (album: SavedAlbum) => void;
}>) {
  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <View className="flex-row gap-4">
        {album.cover_url ? (
          <Image
            className="h-20 w-20 rounded-[18px] bg-slate-100 dark:bg-slate-800"
            resizeMode="cover"
            source={{ uri: album.cover_url }}
          />
        ) : (
          <View className="h-20 w-20 items-center justify-center rounded-[18px] bg-slate-100 dark:bg-slate-800">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400">
              {album.source}
            </Text>
          </View>
        )}

        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{album.title}</Text>
          <Text className="mt-1 text-sm text-slate-600 dark:text-slate-300">{album.artist}</Text>
          <Text className="mt-1 text-sm text-slate-500 dark:text-slate-400">
            {album.release_date ?? 'Unknown release date'}
          </Text>
          <Text className="mt-2 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
            {album.source} • {album.track_count} tracks
          </Text>
          <Text className="mt-2 text-xs text-slate-400 dark:text-slate-500">Saved {formatDate(album.created_at)}</Text>
        </View>
      </View>

      <Pressable
        accessibilityRole="button"
        className="mt-4 rounded-full border border-rose-200 bg-rose-50 px-4 py-3 active:bg-rose-100"
        disabled={isRemoving}
        onPress={() => {
          onRemove(album);
        }}
      >
        <Text className="text-center text-sm font-semibold text-rose-700">
          {isRemoving ? 'Removing album...' : 'Remove album'}
        </Text>
      </Pressable>
    </View>
  );
}

function PlaylistLibraryCard({
  currentPlayMode,
  isCurrentPlaylist,
  isRemoving,
  isStarting,
  isPlaying,
  onPlay,
  onRemove,
  onShuffle,
  playlist,
}: Readonly<{
  currentPlayMode: PlayerPlayMode;
  isCurrentPlaylist: boolean;
  isRemoving: boolean;
  isStarting: boolean;
  isPlaying: boolean;
  onPlay: (playlist: LibraryPlaylist) => void;
  onRemove: (playlist: LibraryPlaylist) => void;
  onShuffle: (playlist: LibraryPlaylist) => void;
  playlist: LibraryPlaylist;
}>) {
  let playLabel = 'Play playlist';
  if (isStarting) {
    playLabel = 'Loading...';
  } else if (isCurrentPlaylist && isPlaying) {
    playLabel = 'Pause playlist';
  } else if (isCurrentPlaylist) {
    playLabel = 'Resume playlist';
  }

  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <View className="flex-row items-start justify-between gap-4">
        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{playlist.name}</Text>
          <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
            {playlist.description ?? 'No description yet.'}
          </Text>
          <Text className="mt-3 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
            {playlist.item_count} items • {playlist.is_public ? 'Public' : 'Private'}
          </Text>
          <Text className="mt-2 text-xs text-slate-400 dark:text-slate-500">
            Updated {formatDate(playlist.updated_at)}
          </Text>
        </View>
        <View className="rounded-full bg-slate-100 px-3 py-2 dark:bg-slate-800">
          <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-600 dark:text-slate-300">
            Playlist
          </Text>
        </View>
      </View>

      <View className="mt-4 flex-row gap-3">
        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
          disabled={isStarting}
          onPress={() => {
            onPlay(playlist);
          }}
        >
          <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
            {playLabel}
          </Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-teal-200 bg-teal-50 px-4 py-3 active:bg-teal-100"
          disabled={isStarting}
          onPress={() => {
            onShuffle(playlist);
          }}
        >
          <Text className="text-center text-sm font-semibold text-teal-700">
            {isCurrentPlaylist && currentPlayMode === 'shuffle' ? 'Shuffle active' : 'Shuffle'}
          </Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="rounded-full border border-rose-200 bg-rose-50 px-4 py-3 active:bg-rose-100"
          disabled={isRemoving}
          onPress={() => {
            onRemove(playlist);
          }}
        >
          <Text className="text-center text-sm font-semibold text-rose-700">
            {isRemoving ? 'Deleting...' : 'Delete'}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

function LibraryLoginState({
  onLogin,
  onRegister,
}: Readonly<{
  onLogin: () => void;
  onRegister: () => void;
}>) {
  return (
    <View className="mt-4 rounded-[24px] bg-white px-4 py-5 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <Text className="text-lg font-semibold text-slate-900 dark:text-slate-100">Login required</Text>
      <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
        Your playlists, albums, tracks, and favourites are loaded from the backend account.
      </Text>

      <Pressable
        accessibilityRole="button"
        className="mt-5 rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
        onPress={onLogin}
      >
        <Text className="text-center text-base font-semibold text-white">Login</Text>
      </Pressable>

      <Pressable
        accessibilityRole="button"
        className="mt-3 rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
        onPress={onRegister}
      >
        <Text className="text-center text-base font-semibold text-slate-700 dark:text-slate-200">Register</Text>
      </Pressable>
    </View>
  );
}

function ActiveLibrarySection({
  activeSection,
  albums,
  deletingItemKey,
  favouriteTracks,
  currentPlayMode,
  currentPlaylistId,
  isPlaying,
  onPlayPlaylist,
  onPlayTrack,
  onRemoveAlbum,
  onRemovePlaylist,
  onRemoveTrack,
  playlistActionKey,
  playlists,
  tracks,
  currentTrackKey,
}: Readonly<{
  activeSection: LibrarySection;
  albums: SavedAlbum[];
  currentPlayMode: PlayerPlayMode;
  currentPlaylistId: string | null;
  deletingItemKey: string | null;
  favouriteTracks: SavedTrack[];
  isPlaying: boolean;
  onPlayPlaylist: (playlist: LibraryPlaylist, playMode: PlayerPlayMode) => void;
  onPlayTrack: (track: SavedTrack) => void;
  onRemoveAlbum: (album: SavedAlbum) => void;
  onRemovePlaylist: (playlist: LibraryPlaylist) => void;
  onRemoveTrack: (track: SavedTrack) => void;
  playlistActionKey: string | null;
  playlists: LibraryPlaylist[];
  tracks: SavedTrack[];
  currentTrackKey: string | null;
}>) {
  if (activeSection === 'playlists') {
    return playlists.length === 0 ? (
      <EmptyLibraryState
        description="Create playlists from the backend flow and they will appear here."
        title="No playlists yet"
      />
    ) : (
      <>
        {playlists.map((playlist) => (
          <PlaylistLibraryCard
            currentPlayMode={currentPlayMode}
            isCurrentPlaylist={currentPlaylistId === playlist.id}
            isRemoving={deletingItemKey === `playlist:${playlist.id}`}
            isStarting={playlistActionKey === `playlist:${playlist.id}`}
            isPlaying={isPlaying}
            key={playlist.id}
            onPlay={(selectedPlaylist) => {
              onPlayPlaylist(selectedPlaylist, 'normal');
            }}
            onRemove={onRemovePlaylist}
            onShuffle={(selectedPlaylist) => {
              onPlayPlaylist(selectedPlaylist, 'shuffle');
            }}
            playlist={playlist}
          />
        ))}
      </>
    );
  }

  if (activeSection === 'albums') {
    return albums.length === 0 ? (
      <EmptyLibraryState
        description="Albums you save from Browse will show up in this section."
        title="No albums in your library"
      />
    ) : (
      <>
        {albums.map((album) => (
          <AlbumLibraryCard
            album={album}
            isRemoving={deletingItemKey === `album:${album.id}`}
            key={album.id}
            onRemove={onRemoveAlbum}
          />
        ))}
      </>
    );
  }

  if (activeSection === 'tracks') {
    return tracks.length === 0 ? (
      <EmptyLibraryState
        description="Tracks you add from external providers will show up here."
        title="No library tracks yet"
      />
    ) : (
      <>
        {tracks.map((track) => (
          <TrackLibraryCard
            isRemoving={deletingItemKey === `track:${track.id}`}
            isCurrentTrack={currentTrackKey === `${track.source}:${track.track_id}`}
            isPlaying={isPlaying}
            key={track.id}
            onPlay={onPlayTrack}
            onRemove={onRemoveTrack}
            showFavouriteBadge={false}
            track={track}
          />
        ))}
      </>
    );
  }

  return favouriteTracks.length === 0 ? (
    <EmptyLibraryState
      description="Saved tracks are treated as favourites, but none have been added yet."
      title="No favourites yet"
    />
  ) : (
    <>
      {favouriteTracks.map((track) => (
        <TrackLibraryCard
          isRemoving={deletingItemKey === `track:${track.id}`}
          isCurrentTrack={currentTrackKey === `${track.source}:${track.track_id}`}
          isPlaying={isPlaying}
          key={track.id}
          onPlay={onPlayTrack}
          onRemove={onRemoveTrack}
          showFavouriteBadge
          track={track}
        />
      ))}
    </>
  );
}

export function LibraryScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { authSession, backendUrl } = useSettings();
  const {
    currentPlayMode,
    currentPlaylistId,
    currentTrack,
    isPlaying,
    playPlaylist,
    playTrack,
    togglePlayPause,
  } = usePlayer();
  const [activeSection, setActiveSection] = useState<LibrarySection>('tracks');
  const [tracks, setTracks] = useState<SavedTrack[]>([]);
  const [albums, setAlbums] = useState<SavedAlbum[]>([]);
  const [playlists, setPlaylists] = useState<LibraryPlaylist[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [deletingItemKey, setDeletingItemKey] = useState<string | null>(null);
  const [playlistActionKey, setPlaylistActionKey] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function loadLibrary() {
    if (!authSession) {
      setTracks([]);
      setAlbums([]);
      setPlaylists([]);
      setErrorMessage(null);
      return;
    }

    setIsLoading(true);
    setErrorMessage(null);

    try {
      const [savedTracksResponse, savedAlbumsResponse, playlistsResponse] = await Promise.all([
        fetchSavedTracks(backendUrl, authSession),
        fetchSavedAlbums(backendUrl, authSession),
        fetchLibraryPlaylists(backendUrl, authSession),
      ]);

      setTracks(savedTracksResponse.tracks);
      setAlbums(savedAlbumsResponse);
      setPlaylists(playlistsResponse.playlists);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to load your library.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    void loadLibrary();
  }, [authSession, backendUrl]);

  const favouriteTracks = useMemo(() => tracks, [tracks]);
  const currentTrackKey = currentTrack?.key ?? null;
  const sectionCounts: Record<LibrarySection, number> = {
    playlists: playlists.length,
    albums: albums.length,
    tracks: tracks.length,
    favourites: favouriteTracks.length,
  };
  const activeSectionMeta =
    LIBRARY_SECTIONS.find((section) => section.key === activeSection) ?? LIBRARY_SECTIONS[0];

  async function handlePlayTrack(track: SavedTrack) {
    const playerKey = `${track.source}:${track.track_id}`;

    if (currentTrack?.key === playerKey) {
      togglePlayPause();
      return;
    }

    if (track.source === 'spotify') {
      setErrorMessage(
        'Spotify playback from saved tracks is only available for tracks with a preview clip.',
      );
      return;
    }

    if (!authSession) {
      return;
    }

    try {
      const streamUrl = await fetchTrackStreamUrl(backendUrl, authSession, track.track_id, track.source);
      playTrack({
        id: track.track_id,
        key: playerKey,
        title: track.title,
        artist: track.artist,
        album: track.album,
        artworkUrl: track.cover_url,
        duration: track.duration,
        source: track.source,
        url: streamUrl,
      });
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to play track.');
    }
  }

  function createQueueTracks(playlist: LibraryPlaylist, items: LibraryPlaylistItem[]): QueueTrack[] {
    return items
      .filter((item) => !item.is_playlist && typeof item.source === 'string' && item.source.length > 0)
      .map((item) => ({
        album: item.album ?? undefined,
        artist: item.artist ?? 'Unknown Artist',
        artworkUrl: item.cover_url,
        description: playlist.description ?? playlist.name,
        duration: item.duration ?? undefined,
        id: item.item_id,
        key: `${item.source}:${item.item_id}`,
        source: item.source ?? 'unknown',
        title: item.title ?? 'Unknown Track',
      }));
  }

  function handlePlayPlaylist(playlist: LibraryPlaylist, playMode: PlayerPlayMode) {
    if (!authSession) {
      return;
    }

    const shouldToggleCurrentPlaylist = currentPlaylistId === playlist.id && currentPlayMode === playMode;

    if (shouldToggleCurrentPlaylist) {
      togglePlayPause();
      return;
    }

    void (async () => {
      const actionKey = `playlist:${playlist.id}`;
      setPlaylistActionKey(actionKey);
      setErrorMessage(null);

      try {
        const items = await fetchLibraryPlaylistItems(backendUrl, authSession, playlist.id);
        const queueTracks = createQueueTracks(playlist, items);

        if (queueTracks.length === 0) {
          throw new Error('This playlist does not contain any playable track items yet.');
        }

        await playPlaylist({
          description: playlist.description ?? undefined,
          playMode,
          playlistId: playlist.id,
          playlistName: playlist.name,
          resolveTrack: async (queuedTrack) => {
            const streamUrl = await fetchTrackStreamUrl(
              backendUrl,
              authSession,
              queuedTrack.id,
              queuedTrack.source,
            );

            return {
              ...queuedTrack,
              url: streamUrl,
            };
          },
          tracks: queueTracks,
        });
      } catch (error) {
        setErrorMessage(error instanceof Error ? error.message : 'Failed to play playlist.');
      } finally {
        setPlaylistActionKey((currentKey) => (currentKey === actionKey ? null : currentKey));
      }
    })();
  }

  async function removeTrackFromLibrary(track: SavedTrack) {
    if (!authSession) {
      return;
    }

    const itemKey = `track:${track.id}`;
    setDeletingItemKey(itemKey);

    try {
      await deleteSavedTrack(backendUrl, authSession, track.id);
      setTracks((currentTracks) => currentTracks.filter((item) => item.id !== track.id));
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to remove track.');
    } finally {
      setDeletingItemKey((currentKey) => (currentKey === itemKey ? null : currentKey));
    }
  }

  async function removeAlbumFromLibrary(album: SavedAlbum) {
    if (!authSession) {
      return;
    }

    const itemKey = `album:${album.id}`;
    setDeletingItemKey(itemKey);

    try {
      await deleteSavedAlbum(backendUrl, authSession, album.id);
      setAlbums((currentAlbums) => currentAlbums.filter((item) => item.id !== album.id));
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to remove album.');
    } finally {
      setDeletingItemKey((currentKey) => (currentKey === itemKey ? null : currentKey));
    }
  }

  async function removePlaylistFromLibrary(playlist: LibraryPlaylist) {
    if (!authSession) {
      return;
    }

    const itemKey = `playlist:${playlist.id}`;
    setDeletingItemKey(itemKey);

    try {
      await deleteLibraryPlaylist(backendUrl, authSession, playlist.id);
      setPlaylists((currentPlaylists) => currentPlaylists.filter((item) => item.id !== playlist.id));
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to delete playlist.');
    } finally {
      setDeletingItemKey((currentKey) => (currentKey === itemKey ? null : currentKey));
    }
  }

  function handleRemoveTrack(track: SavedTrack) {
    if (!authSession) {
      return;
    }

    Alert.alert('Remove track', `Remove "${track.title}" from your library?`, [
      {
        style: 'cancel',
        text: 'Cancel',
      },
      {
        style: 'destructive',
        text: 'Remove',
        onPress: () => {
          void removeTrackFromLibrary(track);
        },
      },
    ]);
  }

  function handleRemoveAlbum(album: SavedAlbum) {
    if (!authSession) {
      return;
    }

    Alert.alert('Remove album', `Remove "${album.title}" from your library?`, [
      {
        style: 'cancel',
        text: 'Cancel',
      },
      {
        style: 'destructive',
        text: 'Remove',
        onPress: () => {
          void removeAlbumFromLibrary(album);
        },
      },
    ]);
  }

  function handleRemovePlaylist(playlist: LibraryPlaylist) {
    if (!authSession) {
      return;
    }

    Alert.alert('Delete playlist', `Delete playlist "${playlist.name}"?`, [
      {
        style: 'cancel',
        text: 'Cancel',
      },
      {
        style: 'destructive',
        text: 'Delete',
        onPress: () => {
          void removePlaylistFromLibrary(playlist);
        },
      },
    ]);
  }

  return (
    <SafeAreaView className="flex-1 bg-slate-50 dark:bg-slate-950" edges={['left', 'right']}>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, paddingTop: 16 }}
      >
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500 dark:text-slate-400">
            Library
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900 dark:text-slate-100">Your Music Library</Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-400">
            Switch between playlists, albums, tracks, and favourites without leaving the page.
          </Text>
        </View>

        {authSession ? (
          <>
            <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
              <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
                Sections
              </Text>

              <ScrollView className="mt-4" horizontal showsHorizontalScrollIndicator={false}>
                {LIBRARY_SECTIONS.map((section) => (
                  <LibrarySectionButton
                    key={section.key}
                    active={activeSection === section.key}
                    count={sectionCounts[section.key]}
                    label={section.label}
                    onPress={() => {
                      setActiveSection(section.key);
                    }}
                  />
                ))}
              </ScrollView>

              <View className="mt-4 rounded-[20px] bg-slate-50 px-4 py-4 dark:bg-slate-950">
                <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{activeSectionMeta.label}</Text>
                <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
                  {activeSectionMeta.subtitle}
                </Text>

                <Pressable
                  accessibilityRole="button"
                  className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-900 dark:active:bg-slate-800"
                  disabled={isLoading}
                  onPress={() => {
                    void loadLibrary();
                  }}
                >
                  <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
                    Refresh library
                  </Text>
                </Pressable>
              </View>
            </View>

            {errorMessage ? (
              <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
                <Text className="text-sm font-semibold text-rose-900">Library failed to load</Text>
                <Text className="mt-1 text-sm text-rose-700">{errorMessage}</Text>
              </View>
            ) : null}

            <View className="mt-4">
              {isLoading ? (
                <View className="rounded-[24px] bg-white px-5 py-10 shadow-sm shadow-slate-200">
                  <ActivityIndicator color="#0f766e" />
                </View>
              ) : (
                <ActiveLibrarySection
                  activeSection={activeSection}
                  albums={albums}
                  currentPlayMode={currentPlayMode}
                  currentPlaylistId={currentPlaylistId}
                  currentTrackKey={currentTrackKey}
                  deletingItemKey={deletingItemKey}
                  favouriteTracks={favouriteTracks}
                  isPlaying={isPlaying}
                  onPlayPlaylist={handlePlayPlaylist}
                  onPlayTrack={handlePlayTrack}
                  onRemoveAlbum={handleRemoveAlbum}
                  onRemovePlaylist={handleRemovePlaylist}
                  onRemoveTrack={handleRemoveTrack}
                  playlistActionKey={playlistActionKey}
                  playlists={playlists}
                  tracks={tracks}
                />
              )}
            </View>
          </>
        ) : (
          <LibraryLoginState
            onLogin={() => {
              navigation.navigate('Login');
            }}
            onRegister={() => {
              navigation.navigate('Register');
            }}
          />
        )}
      </ScrollView>
    </SafeAreaView>
  );
}