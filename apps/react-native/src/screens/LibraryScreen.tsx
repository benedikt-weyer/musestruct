import { useEffect, useMemo, useState } from 'react';
import { useNavigation } from '@react-navigation/native';
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
import {
  fetchLibraryPlaylists,
  fetchSavedAlbums,
  fetchSavedTracks,
} from '../services/libraryApi';
import { fetchTrackStreamUrl } from '../services/streamingLibraryApi';
import type {
  LibraryPlaylist,
  LibrarySection,
  SavedAlbum,
  SavedTrack,
} from '../types/library';

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
    ? 'mr-3 rounded-full bg-slate-900 px-4 py-3'
    : 'mr-3 rounded-full border border-slate-200 bg-white px-4 py-3';
  const labelClassName = active
    ? 'text-sm font-semibold text-white'
    : 'text-sm font-semibold text-slate-700';
  const countClassName = active
    ? 'mt-1 text-xs font-semibold uppercase tracking-[1px] text-slate-300'
    : 'mt-1 text-xs font-semibold uppercase tracking-[1px] text-slate-400';

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
    <View className="rounded-[24px] border border-dashed border-slate-300 bg-white px-5 py-8">
      <Text className="text-lg font-semibold text-slate-900">{title}</Text>
      <Text className="mt-2 text-sm leading-6 text-slate-600">{description}</Text>
    </View>
  );
}

function TrackLibraryCard({
  isCurrentTrack,
  isPlaying,
  onPlay,
  showFavouriteBadge,
  track,
}: Readonly<{
  isCurrentTrack: boolean;
  isPlaying: boolean;
  onPlay: (track: SavedTrack) => void;
  showFavouriteBadge: boolean;
  track: SavedTrack;
}>) {
  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
      <View className="flex-row gap-4">
        {track.cover_url ? (
          <Image
            className="h-16 w-16 rounded-[18px] bg-slate-100"
            resizeMode="cover"
            source={{ uri: track.cover_url }}
          />
        ) : (
          <View className="h-16 w-16 items-center justify-center rounded-[18px] bg-slate-100">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500">
              {track.source}
            </Text>
          </View>
        )}

        <View className="flex-1">
          <View className="flex-row items-start justify-between gap-3">
            <Text className="flex-1 text-base font-semibold text-slate-900">{track.title}</Text>
            {showFavouriteBadge ? (
              <View className="rounded-full bg-rose-100 px-3 py-1">
                <Text className="text-xs font-semibold uppercase tracking-[1px] text-rose-700">
                  Favourite
                </Text>
              </View>
            ) : null}
          </View>
          <Text className="mt-1 text-sm text-slate-600">{track.artist}</Text>
          <Text className="mt-1 text-sm text-slate-500">{track.album}</Text>
          <View className="mt-3 flex-row items-center justify-between">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-400">
              {track.source}
            </Text>
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-400">
              {formatDuration(track.duration)}
            </Text>
          </View>
          <Text className="mt-2 text-xs text-slate-400">Saved {formatDate(track.created_at)}</Text>
        </View>
      </View>

      <Pressable
        accessibilityRole="button"
        className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100"
        onPress={() => {
          onPlay(track);
        }}
      >
        <Text className="text-center text-sm font-semibold text-slate-700">
          {isCurrentTrack && isPlaying ? 'Pause track' : isCurrentTrack ? 'Resume track' : 'Play track'}
        </Text>
      </Pressable>
    </View>
  );
}

function AlbumLibraryCard({ album }: Readonly<{ album: SavedAlbum }>) {
  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
      <View className="flex-row gap-4">
        {album.cover_url ? (
          <Image
            className="h-20 w-20 rounded-[18px] bg-slate-100"
            resizeMode="cover"
            source={{ uri: album.cover_url }}
          />
        ) : (
          <View className="h-20 w-20 items-center justify-center rounded-[18px] bg-slate-100">
            <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500">
              {album.source}
            </Text>
          </View>
        )}

        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900">{album.title}</Text>
          <Text className="mt-1 text-sm text-slate-600">{album.artist}</Text>
          <Text className="mt-1 text-sm text-slate-500">
            {album.release_date ?? 'Unknown release date'}
          </Text>
          <Text className="mt-2 text-xs font-semibold uppercase tracking-[1px] text-slate-400">
            {album.source} • {album.track_count} tracks
          </Text>
          <Text className="mt-2 text-xs text-slate-400">Saved {formatDate(album.created_at)}</Text>
        </View>
      </View>
    </View>
  );
}

function PlaylistLibraryCard({ playlist }: Readonly<{ playlist: LibraryPlaylist }>) {
  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
      <View className="flex-row items-start justify-between gap-4">
        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900">{playlist.name}</Text>
          <Text className="mt-1 text-sm leading-6 text-slate-600">
            {playlist.description ?? 'No description yet.'}
          </Text>
          <Text className="mt-3 text-xs font-semibold uppercase tracking-[1px] text-slate-400">
            {playlist.item_count} items • {playlist.is_public ? 'Public' : 'Private'}
          </Text>
          <Text className="mt-2 text-xs text-slate-400">
            Updated {formatDate(playlist.updated_at)}
          </Text>
        </View>
        <View className="rounded-full bg-slate-100 px-3 py-2">
          <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-600">
            Playlist
          </Text>
        </View>
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
    <View className="mt-4 rounded-[24px] bg-white px-4 py-5 shadow-sm shadow-slate-200">
      <Text className="text-lg font-semibold text-slate-900">Login required</Text>
      <Text className="mt-2 text-sm leading-6 text-slate-600">
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
        className="mt-3 rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100"
        onPress={onRegister}
      >
        <Text className="text-center text-base font-semibold text-slate-700">Register</Text>
      </Pressable>
    </View>
  );
}

function ActiveLibrarySection({
  activeSection,
  albums,
  favouriteTracks,
  isPlaying,
  onPlayTrack,
  playlists,
  tracks,
  currentTrackKey,
}: Readonly<{
  activeSection: LibrarySection;
  albums: SavedAlbum[];
  favouriteTracks: SavedTrack[];
  isPlaying: boolean;
  onPlayTrack: (track: SavedTrack) => void;
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
      <>{playlists.map((playlist) => <PlaylistLibraryCard key={playlist.id} playlist={playlist} />)}</>
    );
  }

  if (activeSection === 'albums') {
    return albums.length === 0 ? (
      <EmptyLibraryState
        description="Albums you save from Browse will show up in this section."
        title="No albums in your library"
      />
    ) : (
      <>{albums.map((album) => <AlbumLibraryCard key={album.id} album={album} />)}</>
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
            isCurrentTrack={currentTrackKey === `${track.source}:${track.track_id}`}
            isPlaying={isPlaying}
            key={track.id}
            onPlay={onPlayTrack}
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
          isCurrentTrack={currentTrackKey === `${track.source}:${track.track_id}`}
          isPlaying={isPlaying}
          key={track.id}
          onPlay={onPlayTrack}
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
  const { currentTrack, isPlaying, playTrack, togglePlayPause } = usePlayer();
  const [activeSection, setActiveSection] = useState<LibrarySection>('tracks');
  const [tracks, setTracks] = useState<SavedTrack[]>([]);
  const [albums, setAlbums] = useState<SavedAlbum[]>([]);
  const [playlists, setPlaylists] = useState<LibraryPlaylist[]>([]);
  const [isLoading, setIsLoading] = useState(false);
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

  return (
    <SafeAreaView className="flex-1 bg-slate-50" edges={['left', 'right']}>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, paddingTop: 16 }}
      >
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500">
            Library
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900">Your Music Library</Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600">
            Switch between playlists, albums, tracks, and favourites without leaving the page.
          </Text>
        </View>

        {authSession ? (
          <>
            <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
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

              <View className="mt-4 rounded-[20px] bg-slate-50 px-4 py-4">
                <Text className="text-base font-semibold text-slate-900">{activeSectionMeta.label}</Text>
                <Text className="mt-1 text-sm leading-6 text-slate-600">
                  {activeSectionMeta.subtitle}
                </Text>

                <Pressable
                  accessibilityRole="button"
                  className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100"
                  disabled={isLoading}
                  onPress={() => {
                    void loadLibrary();
                  }}
                >
                  <Text className="text-center text-sm font-semibold text-slate-700">
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
                  currentTrackKey={currentTrackKey}
                  favouriteTracks={favouriteTracks}
                  isPlaying={isPlaying}
                  onPlayTrack={handlePlayTrack}
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