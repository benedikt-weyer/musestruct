import { useCallback, useEffect, useState } from 'react';
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

import { PLAYABLE_AUDIO_EXTENSIONS } from '../constants/audio';
import { PlaylistArtwork } from '../components/PlaylistArtwork';
import { usePlayer } from '../context/PlayerContext';
import { useSettings } from '../context/SettingsContext';
import { MusicFolderAccess } from '../native/MusicFolderAccess';
import type { RootStackParamList } from '../navigation/types';
import {
  addFavouriteTrack,
  deleteFavouriteTrack,
  deleteLibraryPlaylist,
  deleteSavedTrack,
  fetchFavouriteTracks,
  fetchLibraryPlaylistItems,
  fetchLibraryPlaylists,
  fetchSavedTracks,
  refreshWatchedPlaylist,
} from '../services/libraryApi';
import { fetchStreamingTrack, fetchTrackStreamUrl } from '../services/streamingLibraryApi';
import type { FavouriteTrack, LibraryPlaylist, LibraryPlaylistItem, LibrarySection, SavedTrack } from '../types/library';
import type { MusicFile } from '../types/music';
import type { PlayerPlayMode, QueueTrack } from '../types/player';

type LibrarySectionOption = {
  key: LibrarySection;
  label: string;
  subtitle: string;
};

const LIBRARY_SECTIONS: LibrarySectionOption[] = [
  {
    key: 'local',
    label: 'Local',
    subtitle: 'Device-folder tracks kept fully isolated from the backend library.',
  },
  {
    key: 'favourites',
    label: 'Favourites',
    subtitle: 'Hearted tracks layered on top of your saved library tracks.',
  },
  {
    key: 'playlists',
    label: 'Playlists',
    subtitle: 'Editable playlists and watched read-only imports.',
  },
  {
    key: 'tracks',
    label: 'Tracks',
    subtitle: 'Your saved user tracks backed by canonical matches.',
  },
];

const LIBRARY_TRACKS_PAGE_SIZE = 50;

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

function formatFileSize(size: number) {
  if (size <= 0) {
    return 'Unknown size';
  }

  const units = ['B', 'KB', 'MB', 'GB'];
  let value = size;
  let unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  return `${value.toFixed(value >= 10 || unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

function formatModifiedAt(modifiedAt: number) {
  if (!modifiedAt) {
    return 'Unknown date';
  }

  return new Date(modifiedAt).toLocaleDateString();
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
  heartLabel,
  isRemoving,
  isCurrentTrack,
  isUpdatingFavourite,
  isPlaying,
  onHeart,
  onPlay,
  onRemove,
  track,
}: Readonly<{
  heartLabel?: string;
  isRemoving: boolean;
  isCurrentTrack: boolean;
  isUpdatingFavourite?: boolean;
  isPlaying: boolean;
  onHeart?: (track: SavedTrack) => void;
  onPlay: (track: SavedTrack) => void;
  onRemove: (track: SavedTrack) => void;
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
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{track.title}</Text>
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

        {onHeart ? (
          <Pressable
            accessibilityRole="button"
            className="rounded-full border border-rose-200 bg-rose-50 px-4 py-3 active:bg-rose-100"
            disabled={isUpdatingFavourite}
            onPress={() => {
              onHeart(track);
            }}
          >
            <Text className="text-center text-sm font-semibold text-rose-700">
              {isUpdatingFavourite ? 'Updating...' : heartLabel ?? 'Heart'}
            </Text>
          </Pressable>
        ) : null}

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

function mapFavouriteToSavedTrack(track: FavouriteTrack): SavedTrack {
  return {
    id: track.user_track_id,
    canonical_track_id: track.canonical_track_id,
    track_id: track.track_id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration,
    source: track.source,
    cover_url: track.cover_url,
    is_favourite: true,
    created_at: track.created_at,
    updated_at: track.updated_at,
  };
}

function LocalTrackLibraryCard({
  file,
  isCurrentTrack,
  isPlaying,
  onPlay,
}: Readonly<{
  file: MusicFile;
  isCurrentTrack: boolean;
  isPlaying: boolean;
  onPlay: (file: MusicFile) => void;
}>) {
  const playLabel = getTrackPlayLabel(isCurrentTrack, isPlaying);

  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <View className="flex-row items-start justify-between gap-3">
        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{file.name}</Text>
          <Text className="mt-1 text-sm text-slate-500 dark:text-slate-400">{file.pathLabel}</Text>
        </View>
        <View className="rounded-full bg-teal-100 px-3 py-1 dark:bg-teal-950/60">
          <Text className="text-xs font-semibold uppercase tracking-[1px] text-teal-700">{file.extension}</Text>
        </View>
      </View>

      <View className="mt-4 flex-row justify-between">
        <Text className="text-xs font-medium uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
          {formatFileSize(file.size)}
        </Text>
        <Text className="text-xs font-medium uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
          {formatModifiedAt(file.modifiedAt)}
        </Text>
      </View>

      <Pressable
        accessibilityRole="button"
        className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
        onPress={() => {
          onPlay(file);
        }}
      >
        <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">{playLabel}</Text>
      </Pressable>
    </View>
  );
}

function PlaylistBadge({ label }: Readonly<{ label: string }>) {
  return (
    <View className="rounded-full bg-slate-100 px-3 py-1 dark:bg-slate-800">
      <Text className="text-[11px] font-semibold uppercase tracking-[1px] text-slate-600 dark:text-slate-300">
        {label}
      </Text>
    </View>
  );
}

function PlaylistLibraryCard({
  currentPlayMode,
  isCurrentPlaylist,
  isRefreshing,
  isRemoving,
  isStarting,
  isPlaying,
  onOpen,
  onPlay,
  onRefresh,
  onRemove,
  onShuffle,
  playlist,
}: Readonly<{
  currentPlayMode: PlayerPlayMode;
  isCurrentPlaylist: boolean;
  isRefreshing: boolean;
  isRemoving: boolean;
  isStarting: boolean;
  isPlaying: boolean;
  onOpen: (playlist: LibraryPlaylist) => void;
  onPlay: (playlist: LibraryPlaylist) => void;
  onRefresh: (playlist: LibraryPlaylist) => void;
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
      <Pressable accessibilityRole="button" onPress={() => {
        onOpen(playlist);
      }}>
        <View className="flex-row items-start gap-4">
          <PlaylistArtwork
            fallbackLabel={playlist.source ?? 'playlist'}
            previewCoverUrls={playlist.preview_cover_urls}
            size={80}
          />

          <View className="flex-1">
            <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{playlist.name}</Text>
            <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
              {playlist.description ?? 'No description yet.'}
            </Text>
            <View className="mt-3 flex-row flex-wrap gap-2">
              <PlaylistBadge label={`${playlist.item_count} items`} />
              <PlaylistBadge label={playlist.is_public ? 'Public' : 'Private'} />
              {playlist.is_read_only ? <PlaylistBadge label="Read only" /> : null}
              {playlist.is_watched ? <PlaylistBadge label="Watched" /> : null}
              {playlist.source ? <PlaylistBadge label={playlist.source} /> : null}
            </View>
            <Text className="mt-2 text-xs text-slate-400 dark:text-slate-500">
              {playlist.is_watched && playlist.last_synced_at
                ? `Last synced ${formatDate(playlist.last_synced_at)}`
                : `Updated ${formatDate(playlist.updated_at)}`}
            </Text>
          </View>
        </View>
      </Pressable>

      <View className="mt-4 flex-row flex-wrap gap-3">
        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
          disabled={isStarting || isRefreshing}
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
          disabled={isStarting || isRefreshing}
          onPress={() => {
            onShuffle(playlist);
          }}
        >
          <Text className="text-center text-sm font-semibold text-teal-700">
            {isCurrentPlaylist && currentPlayMode === 'shuffle' ? 'Shuffle active' : 'Shuffle'}
          </Text>
        </Pressable>

        {playlist.is_watched ? (
          <Pressable
            accessibilityRole="button"
            className="rounded-full border border-sky-200 bg-sky-50 px-4 py-3 active:bg-sky-100"
            disabled={isRefreshing || isStarting}
            onPress={() => {
              onRefresh(playlist);
            }}
          >
            <Text className="text-center text-sm font-semibold text-sky-700">
              {isRefreshing ? 'Refreshing...' : 'Refresh'}
            </Text>
          </Pressable>
        ) : null}

        <Pressable
          accessibilityRole="button"
          className="rounded-full border border-rose-200 bg-rose-50 px-4 py-3 active:bg-rose-100"
          disabled={isRemoving || isRefreshing}
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
        Saved tracks, favourites, and imported playlists are loaded from the backend account.
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
  currentPlayMode,
  currentPlaylistId,
  currentTrackKey,
  deletingItemKey,
  favouriteActionKey,
  favourites,
  isLocalLoading,
  isPlaying,
  localFiles,
  localFolderName,
  localTrackError,
  onOpenPlaylist,
  onPlayPlaylist,
  onPlayLocalTrack,
  onToggleFavourite,
  onPlayTrack,
  onRefreshLocalTracks,
  onRefreshPlaylist,
  onRemovePlaylist,
  onRemoveTrack,
  playlistActionKey,
  playlists,
  refreshingPlaylistId,
  tracks,
}: Readonly<{
  activeSection: LibrarySection;
  currentPlayMode: PlayerPlayMode;
  currentPlaylistId: string | null;
  currentTrackKey: string | null;
  deletingItemKey: string | null;
  favouriteActionKey: string | null;
  favourites: FavouriteTrack[];
  isLocalLoading: boolean;
  isPlaying: boolean;
  localFiles: MusicFile[];
  localFolderName: string | null;
  localTrackError: string | null;
  onOpenPlaylist: (playlist: LibraryPlaylist) => void;
  onPlayPlaylist: (playlist: LibraryPlaylist, playMode: PlayerPlayMode) => void;
  onPlayLocalTrack: (file: MusicFile) => void;
  onToggleFavourite: (track: SavedTrack) => void;
  onPlayTrack: (track: SavedTrack) => void;
  onRefreshLocalTracks: () => void;
  onRefreshPlaylist: (playlist: LibraryPlaylist) => void;
  onRemovePlaylist: (playlist: LibraryPlaylist) => void;
  onRemoveTrack: (track: SavedTrack) => void;
  playlistActionKey: string | null;
  playlists: LibraryPlaylist[];
  refreshingPlaylistId: string | null;
  tracks: SavedTrack[];
}>) {
  if (activeSection === 'local') {
    if (!localFolderName) {
      return (
        <EmptyLibraryState
          description="Choose a device folder in Settings to show isolated local tracks here. These tracks stay outside the backend library and are never saved to the database."
          title="No local folder selected"
        />
      );
    }

    if (localTrackError) {
      return (
        <View className="rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
          <Text className="text-sm font-semibold text-rose-900">Local tracks failed to load</Text>
          <Text className="mt-1 text-sm text-rose-700">{localTrackError}</Text>
          <Pressable
            accessibilityRole="button"
            className="mt-4 rounded-full border border-rose-200 bg-white px-4 py-3 active:bg-rose-100"
            onPress={onRefreshLocalTracks}
          >
            <Text className="text-center text-sm font-semibold text-rose-700">Retry scan</Text>
          </Pressable>
        </View>
      );
    }

    if (isLocalLoading) {
      return (
        <View className="rounded-[24px] bg-white px-5 py-10 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <ActivityIndicator color="#0f766e" />
        </View>
      );
    }

    return localFiles.length === 0 ? (
      <EmptyLibraryState
        description="The selected device folder does not contain any playable local files yet."
        title="No local tracks found"
      />
    ) : (
      <>
        <View className="mb-4 rounded-[20px] bg-slate-50 px-4 py-4 dark:bg-slate-950">
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{localFolderName}</Text>
          <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
            Local tracks are isolated from your backend library. They cannot be favourited, added to playlists, or persisted in the database.
          </Text>
          <Pressable
            accessibilityRole="button"
            className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-900 dark:active:bg-slate-800"
            onPress={onRefreshLocalTracks}
          >
            <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">Refresh local tracks</Text>
          </Pressable>
        </View>
        {localFiles.map((file) => (
          <LocalTrackLibraryCard
            file={file}
            isCurrentTrack={currentTrackKey === `device:${file.id}`}
            isPlaying={isPlaying}
            key={file.id}
            onPlay={onPlayLocalTrack}
          />
        ))}
      </>
    );
  }

  if (activeSection === 'favourites') {
    return favourites.length === 0 ? (
      <EmptyLibraryState
        description="Heart tracks from Browse or your saved tracks list and they will show up here."
        title="No favourites yet"
      />
    ) : (
      <>
        {favourites.map((track) => (
          <TrackLibraryCard
            heartLabel="Unheart"
            isRemoving={deletingItemKey === `track:${track.user_track_id}`}
            isCurrentTrack={currentTrackKey === `${track.source}:${track.track_id}`}
            isPlaying={isPlaying}
            isUpdatingFavourite={favouriteActionKey === `track:${track.user_track_id}`}
            key={track.id}
            onHeart={onToggleFavourite}
            onPlay={onPlayTrack}
            onRemove={onRemoveTrack}
            track={mapFavouriteToSavedTrack(track)}
          />
        ))}
      </>
    );
  }

  if (activeSection === 'playlists') {
    return playlists.length === 0 ? (
      <EmptyLibraryState
        description="Import watched playlists from Browse or create your own editable playlists."
        title="No playlists yet"
      />
    ) : (
      <>
        {playlists.map((playlist) => (
          <PlaylistLibraryCard
            currentPlayMode={currentPlayMode}
            isCurrentPlaylist={currentPlaylistId === playlist.id}
            isRefreshing={refreshingPlaylistId === playlist.id}
            isRemoving={deletingItemKey === `playlist:${playlist.id}`}
            isStarting={playlistActionKey === `playlist:${playlist.id}`}
            isPlaying={isPlaying}
            key={playlist.id}
            onOpen={onOpenPlaylist}
            onPlay={(selectedPlaylist) => {
              onPlayPlaylist(selectedPlaylist, 'normal');
            }}
            onRefresh={onRefreshPlaylist}
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

  return tracks.length === 0 ? (
    <EmptyLibraryState
      description="Tracks you add from providers will show up here."
      title="No library tracks yet"
    />
  ) : (
    <>
      {tracks.map((track) => (
        <TrackLibraryCard
          heartLabel={track.is_favourite ? 'Unheart' : 'Heart'}
          isRemoving={deletingItemKey === `track:${track.id}`}
          isCurrentTrack={currentTrackKey === `${track.source}:${track.track_id}`}
          isPlaying={isPlaying}
          isUpdatingFavourite={favouriteActionKey === `track:${track.id}`}
          onHeart={onToggleFavourite}
          key={track.id}
          onPlay={onPlayTrack}
          onRemove={onRemoveTrack}
          track={track}
        />
      ))}
    </>
  );
}

export function LibraryScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { authSession, backendUrl, selectedFolder } = useSettings();
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
  const [favourites, setFavourites] = useState<FavouriteTrack[]>([]);
  const [localFiles, setLocalFiles] = useState<MusicFile[]>([]);
  const [tracks, setTracks] = useState<SavedTrack[]>([]);
  const [tracksPage, setTracksPage] = useState(1);
  const [tracksTotalCount, setTracksTotalCount] = useState(0);
  const [playlists, setPlaylists] = useState<LibraryPlaylist[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isLocalLoading, setIsLocalLoading] = useState(false);
  const [deletingItemKey, setDeletingItemKey] = useState<string | null>(null);
  const [favouriteActionKey, setFavouriteActionKey] = useState<string | null>(null);
  const [playlistActionKey, setPlaylistActionKey] = useState<string | null>(null);
  const [refreshingPlaylistId, setRefreshingPlaylistId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [localTrackError, setLocalTrackError] = useState<string | null>(null);

  const loadLibrary = useCallback(async () => {
    if (!authSession) {
      setFavourites([]);
      setTracks([]);
      setTracksTotalCount(0);
      setPlaylists([]);
      setErrorMessage(null);
      return;
    }

    setIsLoading(true);
    setErrorMessage(null);

    try {
      const [savedTracksResponse, favouriteTracksResponse, playlistsResponse] = await Promise.all([
        fetchSavedTracks(backendUrl, authSession, tracksPage, LIBRARY_TRACKS_PAGE_SIZE),
        fetchFavouriteTracks(backendUrl, authSession),
        fetchLibraryPlaylists(backendUrl, authSession),
      ]);

      setFavourites(favouriteTracksResponse.tracks);
      setTracks(savedTracksResponse.tracks);
      setTracksTotalCount(savedTracksResponse.total_count);
      setPlaylists(playlistsResponse.playlists);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to load your library.');
    } finally {
      setIsLoading(false);
    }
  }, [authSession, backendUrl, tracksPage]);

  useEffect(() => {
    void loadLibrary();
  }, [loadLibrary]);

  useEffect(() => {
    setTracksPage(1);
  }, [authSession?.sessionToken, backendUrl]);

  const loadLocalTracks = useCallback(async () => {
    if (!selectedFolder) {
      setLocalFiles([]);
      setLocalTrackError(null);
      return;
    }

    setIsLocalLoading(true);
    setLocalTrackError(null);

    try {
      const nextFiles = await MusicFolderAccess.listPlayableFiles(
        selectedFolder.id,
        [...PLAYABLE_AUDIO_EXTENSIONS],
      );
      setLocalFiles(nextFiles);
    } catch (error) {
      setLocalTrackError(
        error instanceof Error ? error.message : 'The selected folder could not be scanned.',
      );
      setLocalFiles([]);
    } finally {
      setIsLocalLoading(false);
    }
  }, [selectedFolder?.id]);

  useEffect(() => {
    void loadLocalTracks();
  }, [loadLocalTracks]);

  const currentTrackKey = currentTrack?.key ?? null;
  const sectionCounts: Record<LibrarySection, number> = {
    favourites: favourites.length,
    local: localFiles.length,
    playlists: playlists.length,
    tracks: tracksTotalCount,
  };
  const activeSectionMeta =
    LIBRARY_SECTIONS.find((section) => section.key === activeSection) ?? LIBRARY_SECTIONS[0];
  const tracksTotalPages = Math.max(1, Math.ceil(tracksTotalCount / LIBRARY_TRACKS_PAGE_SIZE));
  const hasPreviousTracksPage = tracksPage > 1;
  const hasNextTracksPage = tracksPage < tracksTotalPages;

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
      setErrorMessage(error instanceof Error ? error.message : 'Failed to play track.');
    }
  }

  function handlePlayLocalTrack(file: MusicFile) {
    const playerKey = `device:${file.id}`;

    if (currentTrack?.key === playerKey) {
      togglePlayPause();
      return;
    }

    playTrack({
      id: file.id,
      key: playerKey,
      title: file.name,
      artist: 'Local file',
      album: selectedFolder?.name,
      description: file.pathLabel,
      duration: undefined,
      source: 'device',
      url: file.uri,
    });
  }

  function createQueueTracks(playlist: LibraryPlaylist, items: LibraryPlaylistItem[]): QueueTrack[] {
    return items
      .filter((item) => !item.is_playlist && typeof item.source === 'string' && item.source.length > 0)
      .map((item) => ({
        album: item.album ?? undefined,
        artist: item.artist ?? 'Unknown Artist',
        artworkUrl: item.cover_url ?? undefined,
        description: playlist.description ?? playlist.name,
        duration: item.duration ?? undefined,
        id: item.item_id,
        key: `${item.source}:${item.item_id}`,
        source: item.source ?? 'unknown',
        title: item.title ?? 'Unknown Track',
        userTrackId: item.user_track_id ?? undefined,
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
            const playbackTrack =
              queuedTrack.source === 'tidal'
                ? await fetchStreamingTrack(backendUrl, authSession, queuedTrack.id, queuedTrack.source)
                : null;

            return {
              ...queuedTrack,
              title: playbackTrack?.title ?? queuedTrack.title,
              artist: playbackTrack?.artist ?? queuedTrack.artist,
              album: playbackTrack?.album ?? queuedTrack.album,
              artworkUrl: playbackTrack?.cover_url ?? queuedTrack.artworkUrl,
              duration: playbackTrack?.duration ?? queuedTrack.duration,
              url:
                queuedTrack.source === 'tidal'
                  ? ''
                  : await fetchTrackStreamUrl(
                      backendUrl,
                      authSession,
                      queuedTrack.id,
                      queuedTrack.source,
                    ),
              backendUrl: queuedTrack.source === 'tidal' ? backendUrl : undefined,
              sessionToken: queuedTrack.source === 'tidal' ? authSession.sessionToken : undefined,
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

  async function handleRefreshPlaylist(playlist: LibraryPlaylist) {
    if (!authSession) {
      return;
    }

    setRefreshingPlaylistId(playlist.id);
    try {
      const refreshed = await refreshWatchedPlaylist(backendUrl, authSession, playlist.id);
      setPlaylists((currentPlaylists) =>
        currentPlaylists.map((item) => (item.id === refreshed.id ? refreshed : item)),
      );
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to refresh playlist.');
    } finally {
      setRefreshingPlaylistId((currentId) => (currentId === playlist.id ? null : currentId));
    }
  }

  async function removeTrackFromLibrary(track: SavedTrack) {
    if (!authSession) {
      return;
    }

    const itemKey = `track:${track.id}`;
    setDeletingItemKey(itemKey);

    try {
      await deleteSavedTrack(backendUrl, authSession, track.id);
      const nextTotalCount = Math.max(tracksTotalCount - 1, 0);
      const nextTotalPages = Math.max(1, Math.ceil(nextTotalCount / LIBRARY_TRACKS_PAGE_SIZE));

      if (tracksPage > nextTotalPages) {
        setTracksPage(nextTotalPages);
      } else {
        void loadLibrary();
      }

      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to remove track.');
    } finally {
      setDeletingItemKey((currentKey) => (currentKey === itemKey ? null : currentKey));
    }
  }

  async function toggleFavouriteTrack(track: SavedTrack) {
    if (!authSession) {
      return;
    }

    const itemKey = `track:${track.id}`;
    setFavouriteActionKey(itemKey);

    try {
      if (track.is_favourite) {
        await deleteFavouriteTrack(backendUrl, authSession, track.id);
        setFavourites((currentFavourites) =>
          currentFavourites.filter((item) => item.user_track_id !== track.id),
        );
        setTracks((currentTracks) =>
          currentTracks.map((item) =>
            item.id === track.id ? { ...item, is_favourite: false } : item,
          ),
        );
      } else {
        const favourite = await addFavouriteTrack(backendUrl, authSession, track);
        setFavourites((currentFavourites) => {
          const next = currentFavourites.filter((item) => item.user_track_id !== track.id);
          return [favourite, ...next];
        });
        setTracks((currentTracks) =>
          currentTracks.map((item) =>
            item.id === track.id ? { ...item, is_favourite: true } : item,
          ),
        );
      }
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Failed to update favourite track.');
    } finally {
      setFavouriteActionKey((currentKey) => (currentKey === itemKey ? null : currentKey));
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
            Browse isolated local tracks, saved backend tracks, favourites, and imported playlists.
          </Text>
        </View>

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
              disabled={activeSection === 'local' ? isLocalLoading : isLoading}
              onPress={() => {
                if (activeSection === 'local') {
                  void loadLocalTracks();
                  return;
                }

                void loadLibrary();
              }}
            >
              <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
                {activeSection === 'local' ? 'Refresh local tracks' : 'Refresh library'}
              </Text>
            </Pressable>
          </View>
        </View>

        {activeSection !== 'local' && errorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm font-semibold text-rose-900">Library failed to load</Text>
            <Text className="mt-1 text-sm text-rose-700">{errorMessage}</Text>
          </View>
        ) : null}

        <View className="mt-4">
          {activeSection !== 'local' && !authSession ? (
            <LibraryLoginState
              onLogin={() => {
                navigation.navigate('Login');
              }}
              onRegister={() => {
                navigation.navigate('Register');
              }}
            />
          ) : isLoading && activeSection !== 'local' ? (
            <View className="rounded-[24px] bg-white px-5 py-10 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
              <ActivityIndicator color="#0f766e" />
            </View>
          ) : (
            <ActiveLibrarySection
              activeSection={activeSection}
              currentPlayMode={currentPlayMode}
              currentPlaylistId={currentPlaylistId}
              currentTrackKey={currentTrackKey}
              deletingItemKey={deletingItemKey}
              favouriteActionKey={favouriteActionKey}
              favourites={favourites}
              isLocalLoading={isLocalLoading}
              isPlaying={isPlaying}
              localFiles={localFiles}
              localFolderName={selectedFolder?.name ?? null}
              localTrackError={localTrackError}
              onOpenPlaylist={(playlist) => {
                navigation.navigate('PlaylistDetails', {
                  playlistDescription: playlist.description,
                  playlistId: playlist.id,
                  playlistName: playlist.name,
                });
              }}
              onPlayLocalTrack={handlePlayLocalTrack}
              onPlayPlaylist={handlePlayPlaylist}
              onToggleFavourite={toggleFavouriteTrack}
              onPlayTrack={handlePlayTrack}
              onRefreshLocalTracks={() => {
                void loadLocalTracks();
              }}
              onRefreshPlaylist={handleRefreshPlaylist}
              onRemovePlaylist={handleRemovePlaylist}
              onRemoveTrack={handleRemoveTrack}
              playlistActionKey={playlistActionKey}
              playlists={playlists}
              refreshingPlaylistId={refreshingPlaylistId}
              tracks={tracks}
            />
          )}

          {activeSection === 'tracks' && authSession && tracksTotalCount > 0 ? (
            <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
              <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
                Page {tracksPage} / {tracksTotalPages}
              </Text>
              <Text className="mt-1 text-center text-xs uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
                {tracksTotalCount} saved tracks total
              </Text>

              <View className="mt-4 flex-row gap-3">
                <Pressable
                  accessibilityRole="button"
                  className="flex-1 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 disabled:opacity-50 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
                  disabled={isLoading || !hasPreviousTracksPage}
                  onPress={() => {
                    setTracksPage((currentPage) => Math.max(1, currentPage - 1));
                  }}
                >
                  <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
                    Previous page
                  </Text>
                </Pressable>

                <Pressable
                  accessibilityRole="button"
                  className="flex-1 rounded-full border border-slate-900 bg-slate-900 px-4 py-3 active:bg-slate-700 disabled:opacity-50 dark:border-teal-700 dark:bg-teal-700 dark:active:bg-teal-600"
                  disabled={isLoading || !hasNextTracksPage}
                  onPress={() => {
                    setTracksPage((currentPage) => Math.min(tracksTotalPages, currentPage + 1));
                  }}
                >
                  <Text className="text-center text-sm font-semibold text-white">Next page</Text>
                </Pressable>
              </View>
            </View>
          ) : null}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}
