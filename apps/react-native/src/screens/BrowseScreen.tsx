import { useEffect, useMemo, useState } from 'react';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
  ActivityIndicator,
  Alert,
  Image,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  ToastAndroid,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { PlaylistArtwork } from '../components/PlaylistArtwork';
import { usePlayer } from '../context/PlayerContext';
import { useSettings } from '../context/SettingsContext';
import type { RootStackParamList } from '../navigation/types';
import type { AuthSession } from '../types/auth';
import { addFavouriteStreamingTrack, importProviderPlaylist } from '../services/libraryApi';
import {
  getStoredBrowseSearchScope,
  getStoredBrowseSearchType,
  persistBrowseSearchScope,
  persistBrowseSearchType,
} from '../storage/settingsStorage';
import {
  fetchAvailableServices,
  fetchServiceStatus,
  fetchStreamingPlaylistTracks,
  fetchTrackStreamUrl,
  saveTrackToLibrary,
  searchStreamingCatalog,
} from '../services/streamingLibraryApi';
import type {
  AvailableService,
  ConnectedServiceInfo,
  StreamingAlbum,
  StreamingPlaylist,
  StreamingTrack,
} from '../types/streaming';

type BrowseSearchType = 'track' | 'album' | 'playlist';
type BrowseResultMode = 'all' | BrowseSearchType;
type BrowseSearchScope = 'all' | 'library';

type BrowseSearchRequest = {
  allowEmptyQuery: boolean;
  includeAllTypes: boolean;
  query: string;
  scope: BrowseSearchScope;
  searchType: BrowseSearchType;
  services: string[];
};

function getAllLibraryButtonLabel(searchType: BrowseSearchType) {
  if (searchType === 'track') {
    return 'Search All Tracks In My Library';
  }

  if (searchType === 'album') {
    return 'Search All Albums In My Library';
  }

  return 'Search All Playlists In My Library';
}

function getSearchAllButtonLabel(
  searchType: BrowseSearchType,
  searchScope: BrowseSearchScope,
  isServerOnlySelected: boolean,
) {
  if (isServerOnlySelected) {
    if (searchType === 'track') {
      return 'Search All Tracks On Server';
    }

    if (searchType === 'album') {
      return 'Search All Albums On Server';
    }

    return 'Search All Playlists On Server';
  }

  return getAllLibraryButtonLabel(searchType);
}

function showToast(message: string) {
  if (Platform.OS === 'android') {
    ToastAndroid.show(message, ToastAndroid.SHORT);
    return;
  }

  Alert.alert('Musestruct', message);
}

function formatDuration(duration?: number) {
  if (!duration) {
    return '--:--';
  }

  const minutes = Math.floor(duration / 60);
  const seconds = duration % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

function sortServiceNames(names: string[]) {
  return [...names].sort((left, right) => left.localeCompare(right));
}

function getSearchPlaceholder(searchType: BrowseSearchType, searchScope: BrowseSearchScope) {
  if (searchType === 'track') {
    return searchScope === 'library' ? 'Search saved tracks' : 'Search tracks';
  }

  if (searchType === 'album') {
    return searchScope === 'library' ? 'Search cached provider albums' : 'Search albums';
  }

  return searchScope === 'library' ? 'Search provider library playlists' : 'Search playlists';
}

function getVisibleResultCount(
  resultMode: BrowseResultMode,
  tracks: StreamingTrack[],
  albums: StreamingAlbum[],
  playlists: StreamingPlaylist[],
) {
  if (resultMode === 'all') {
    return tracks.length + albums.length + playlists.length;
  }

  if (resultMode === 'track') {
    return tracks.length;
  }

  if (resultMode === 'album') {
    return albums.length;
  }

  return playlists.length;
}

function getPlaylistPreviewCoverUrls(tracks: StreamingTrack[]) {
  const previewCoverUrls: string[] = [];

  for (const track of tracks) {
    const coverUrl = track.cover_url?.trim();
    if (!coverUrl || previewCoverUrls.includes(coverUrl)) {
      continue;
    }

    previewCoverUrls.push(coverUrl);
    if (previewCoverUrls.length === 4) {
      break;
    }
  }

  return previewCoverUrls;
}

function getEmptyStateMessage({
  isAllProvidersSelected,
  isServerOnlySelected,
  searchScope,
  searchType,
}: Readonly<{
  isAllProvidersSelected: boolean;
  isServerOnlySelected: boolean;
  searchScope: BrowseSearchScope;
  searchType: BrowseSearchType;
}>) {
  const serverOnlyMessages: Record<BrowseResultMode, string> = {
    all: 'Search your server music to see matching tracks, albums, and playlists here.',
    track: 'Search your server music to see matching tracks here.',
    album: 'Search your server music to see matching albums here.',
    playlist: 'Search your server music to see matching playlists here.',
  };
  const libraryMessages: Record<BrowseResultMode, string> = {
    all: 'Search your provider library for tracks, cached albums, and playlists all at once.',
    track: 'Search your saved provider tracks to see matches here.',
    album: 'Search your cached provider albums to see matches here.',
    playlist: 'Search your provider library playlists to see matches here.',
  };
  const allProviderMessages: Record<BrowseResultMode, string> = {
    all: 'Search across all connected providers to see matching tracks, albums, and playlists.',
    track: 'Search across all connected providers to see matching tracks.',
    album: 'Search across all connected providers to see matching albums.',
    playlist: 'Search across all connected providers to see matching playlists.',
  };
  const singleProviderMessages: Record<BrowseResultMode, string> = {
    all: 'Search a connected provider to see matching tracks, albums, and playlists.',
    track: 'Search a connected provider to see matching tracks.',
    album: 'Search a connected provider to see matching albums.',
    playlist: 'Search a connected provider to see matching playlists.',
  };

  if (isServerOnlySelected) {
    return serverOnlyMessages[searchType];
  }

  if (searchScope === 'library') {
    return libraryMessages[searchType];
  }

  if (isAllProvidersSelected) {
    return allProviderMessages[searchType];
  }

  return singleProviderMessages[searchType];
}

function BrowseTrackCard({
  isCurrentTrack,
  isPlaying,
  onFavourite,
  onPlay,
  onSave,
  track,
}: Readonly<{
  isCurrentTrack: boolean;
  isPlaying: boolean;
  onFavourite: (track: StreamingTrack) => void;
  onPlay: (track: StreamingTrack) => void;
  onSave: (track: StreamingTrack) => void;
  track: StreamingTrack;
}>) {
  let playLabel = 'Play track';
  if (isCurrentTrack && isPlaying) {
    playLabel = 'Pause track';
  } else if (isCurrentTrack) {
    playLabel = 'Resume track';
  }

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
        </View>
      </View>

      <View className="mt-4 flex-row gap-3">
        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full bg-slate-900 px-4 py-3 active:bg-slate-700"
          onPress={() => {
            onPlay(track);
          }}
        >
          <Text className="text-center text-sm font-semibold text-white">{playLabel}</Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
          onPress={() => {
            onSave(track);
          }}
        >
          <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">Add track to library</Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="rounded-full border border-rose-200 bg-rose-50 px-4 py-3 active:bg-rose-100"
          onPress={() => {
            onFavourite(track);
          }}
        >
          <Text className="text-center text-sm font-semibold text-rose-700">Heart</Text>
        </Pressable>
      </View>
    </View>
  );
}

function BrowseAlbumCard({
  album,
}: Readonly<{
  album: StreamingAlbum;
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
            {album.release_date ?? 'Unknown release'}
          </Text>
          <Text className="mt-2 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
            {album.source} • {album.tracks.length} tracks
          </Text>
        </View>
      </View>

      <View className="mt-4 rounded-[18px] bg-slate-50 px-4 py-3 dark:bg-slate-950">
        <Text className="text-sm leading-6 text-slate-600 dark:text-slate-400">
          Albums are matched during provider sync and playlist import. They are no longer saved as a separate user library layer.
        </Text>
      </View>
    </View>
  );
}

function BrowsePlaylistCard({
  authSession,
  backendUrl,
  onClone,
  onWatch,
  playlist,
}: Readonly<{
  authSession: AuthSession | null;
  backendUrl: string;
  onClone: (playlist: StreamingPlaylist) => void;
  onWatch: (playlist: StreamingPlaylist) => void;
  playlist: StreamingPlaylist;
}>) {
  const [previewCoverUrls, setPreviewCoverUrls] = useState<string[]>([]);

  useEffect(() => {
    let isCancelled = false;

    if (playlist.cover_url || !authSession || playlist.track_count <= 0) {
      setPreviewCoverUrls([]);
      return () => {
        isCancelled = true;
      };
    }

    void fetchStreamingPlaylistTracks(
      backendUrl,
      authSession,
      playlist.id,
      playlist.source,
      4,
      0,
    )
      .then((tracks) => {
        if (!isCancelled) {
          setPreviewCoverUrls(getPlaylistPreviewCoverUrls(tracks));
        }
      })
      .catch(() => {
        if (!isCancelled) {
          setPreviewCoverUrls([]);
        }
      });

    return () => {
      isCancelled = true;
    };
  }, [authSession, backendUrl, playlist.cover_url, playlist.id, playlist.source, playlist.track_count]);

  return (
    <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <View className="flex-row gap-4">
        <PlaylistArtwork
          coverUrl={playlist.cover_url}
          fallbackLabel={playlist.source}
          previewCoverUrls={previewCoverUrls}
          size={80}
        />

        <View className="flex-1">
          <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{playlist.name}</Text>
          <Text className="mt-1 text-sm text-slate-600 dark:text-slate-300">By {playlist.owner}</Text>
          {playlist.description ? (
            <Text className="mt-1 text-sm text-slate-500 dark:text-slate-400">{playlist.description}</Text>
          ) : null}
          <Text className="mt-2 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
            {playlist.source} • {playlist.track_count} tracks • {playlist.is_public ? 'public' : 'private'}
          </Text>
        </View>
      </View>

      <View className="mt-4 flex-row gap-3">
        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
          onPress={() => {
            onWatch(playlist);
          }}
        >
          <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">Watch playlist</Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-teal-200 bg-teal-50 px-4 py-3 active:bg-teal-100"
          onPress={() => {
            onClone(playlist);
          }}
        >
          <Text className="text-center text-sm font-semibold text-teal-700">Clone playlist</Text>
        </Pressable>
      </View>
    </View>
  );
}

function FilterChip({
  disabled = false,
  isSelected,
  label,
  onPress,
}: Readonly<{
  disabled?: boolean;
  isSelected: boolean;
  label: string;
  onPress: () => void;
}>) {
  let containerClassName = 'rounded-full border border-slate-200 bg-white px-3 py-2 dark:border-slate-700 dark:bg-slate-950';
  let labelClassName = 'text-xs font-semibold uppercase tracking-[1px] text-slate-700 dark:text-slate-200';

  if (disabled) {
    containerClassName = 'rounded-full border border-slate-200 bg-slate-100 px-3 py-2 dark:border-slate-700 dark:bg-slate-800';
    labelClassName = 'text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500';
  }

  if (isSelected) {
    containerClassName = disabled
      ? 'rounded-full border border-slate-200 bg-slate-100 px-3 py-2 dark:border-slate-700 dark:bg-slate-800'
      : 'rounded-full border border-teal-200 bg-teal-50 px-3 py-2 dark:border-teal-900 dark:bg-teal-950/40';
    labelClassName = disabled
      ? 'text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400'
      : 'text-xs font-semibold uppercase tracking-[1px] text-teal-700 dark:text-teal-300';
  }

  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      className={containerClassName}
      onPress={onPress}
    >
      <Text className={labelClassName}>
        {label}
      </Text>
    </Pressable>
  );
}

const SEARCH_PAGE_SIZE = 20;

export function BrowseScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { authSession, backendUrl } = useSettings();
  const { currentTrack, isPlaying, playTrack, togglePlayPause } = usePlayer();
  const [query, setQuery] = useState('');
  const [searchType, setSearchType] = useState<BrowseSearchType>(() => getStoredBrowseSearchType());
  const [resultMode, setResultMode] = useState<BrowseResultMode>('track');
  const [searchScope, setSearchScope] = useState<BrowseSearchScope>(() => getStoredBrowseSearchScope());
  const [availableServices, setAvailableServices] = useState<AvailableService[]>([]);
  const [serviceStatus, setServiceStatus] = useState<ConnectedServiceInfo[]>([]);
  const [selectedServices, setSelectedServices] = useState<string[]>([]);
  const [tracks, setTracks] = useState<StreamingTrack[]>([]);
  const [albums, setAlbums] = useState<StreamingAlbum[]>([]);
  const [playlists, setPlaylists] = useState<StreamingPlaylist[]>([]);
  const [currentPage, setCurrentPage] = useState(0);
  const [totalResults, setTotalResults] = useState(0);
  const [hasSearched, setHasSearched] = useState(false);
  const [isBootstrapping, setIsBootstrapping] = useState(false);
  const [isSearching, setIsSearching] = useState(false);
  const [lastSearchRequest, setLastSearchRequest] = useState<BrowseSearchRequest | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    async function loadServices() {
      if (!authSession) {
        setAvailableServices([]);
        setServiceStatus([]);
        setSelectedServices([]);
        return;
      }

      setIsBootstrapping(true);
      setErrorMessage(null);

      try {
        const [available, status] = await Promise.all([
          fetchAvailableServices(backendUrl, authSession),
          fetchServiceStatus(backendUrl, authSession),
        ]);

        const connectedServiceNames = status.services
          .filter((service) => service.is_connected)
          .map((service) => service.name);

        setAvailableServices(available.services);
        setServiceStatus(status.services);
        setSelectedServices(connectedServiceNames);
      } catch (error) {
        setErrorMessage(
          error instanceof Error ? error.message : 'Failed to load music providers.',
        );
      } finally {
        setIsBootstrapping(false);
      }
    }

    void loadServices();
  }, [authSession, backendUrl]);

  const connectedServices = useMemo(() => {
    const connectedNames = new Set(
      serviceStatus
        .filter((service) => service.is_connected)
        .map((service) => service.name),
    );

    return availableServices.filter((service) => connectedNames.has(service.name));
  }, [availableServices, serviceStatus]);
  const connectedServiceNames = useMemo(
    () => sortServiceNames(connectedServices.map((service) => service.name)),
    [connectedServices],
  );
  const normalizedSelectedServices = useMemo(
    () => sortServiceNames(selectedServices),
    [selectedServices],
  );
  const isAllProvidersSelected =
    connectedServiceNames.length > 0 &&
    connectedServiceNames.length === normalizedSelectedServices.length &&
    connectedServiceNames.every(
      (serviceName, index) => serviceName === normalizedSelectedServices[index],
    );
  const isServerOnlySelected =
    normalizedSelectedServices.length === 1 && normalizedSelectedServices[0] === 'server';

  useEffect(() => {
    if (isServerOnlySelected && searchScope !== 'all') {
      setSearchScope('all');
    }
  }, [isServerOnlySelected, searchScope]);

  useEffect(() => {
    persistBrowseSearchType(searchType);
  }, [searchType]);

  useEffect(() => {
    persistBrowseSearchScope(searchScope);
  }, [searchScope]);

  const searchPlaceholder = getSearchPlaceholder(searchType, searchScope);
  let providerFilterContent = (
    <Text className="mt-2 text-sm leading-6 text-slate-500 dark:text-slate-400">
      No providers are currently connected for this account.
    </Text>
  );

  if (isBootstrapping) {
    providerFilterContent = (
      <View className="mt-3 py-4">
        <ActivityIndicator color="#0f766e" />
      </View>
    );
  } else if (connectedServices.length > 0) {
    providerFilterContent = (
      <View className="mt-2 flex-row flex-wrap gap-2">
        {connectedServices.map((service) => {
          const isSelected = selectedServices.includes(service.name);
          const chipClassName = isSelected
            ? 'rounded-full border border-teal-200 bg-teal-50 px-3 py-2 dark:bg-teal-950/40'
            : 'rounded-full border border-slate-200 bg-white px-3 py-2 dark:border-slate-700 dark:bg-slate-950';
          const textClassName = isSelected
            ? 'text-xs font-semibold uppercase tracking-[1px] text-teal-700'
            : 'text-xs font-semibold uppercase tracking-[1px] text-slate-700 dark:text-slate-200';

          return (
            <Pressable
              key={service.name}
              accessibilityRole="button"
              className={chipClassName}
              onPress={() => {
                toggleService(service.name);
              }}
            >
              <Text className={textClassName}>{service.display_name}</Text>
            </Pressable>
          );
        })}
      </View>
    );
  }

  function toggleService(serviceName: string) {
    setSelectedServices((currentServices) =>
      currentServices.includes(serviceName)
        ? currentServices.filter((name) => name !== serviceName)
        : [...currentServices, serviceName],
    );
  }

  async function handleSearch(
    page = 0,
    options?: {
      allowEmptyQuery?: boolean;
      forceScope?: BrowseSearchScope;
      includeAllTypes?: boolean;
      ignoreQuery?: boolean;
    },
  ) {
    if (!authSession) {
      setErrorMessage('Please log in before browsing providers.');
      return;
    }

    const isPaginationRequest = page > 0 || (page === 0 && currentPage > 0 && !options);
    const request: BrowseSearchRequest =
      isPaginationRequest && lastSearchRequest
        ? lastSearchRequest
        : {
            allowEmptyQuery: options?.allowEmptyQuery ?? false,
            includeAllTypes: options?.includeAllTypes ?? false,
            query: options?.ignoreQuery ? '' : query,
            scope: options?.forceScope ?? searchScope,
            searchType,
            services: selectedServices,
          };

    const trimmedQuery = request.query.trim();
    const allowEmptyQuery = request.allowEmptyQuery;
    const nextScope = request.scope;
    const includeAllTypes = request.includeAllTypes;

    if (!trimmedQuery && !allowEmptyQuery) {
      setErrorMessage('Enter a search term first.');
      return;
    }

    if (request.services.length === 0) {
      setErrorMessage('Select at least one connected provider to search.');
      return;
    }

    setIsSearching(true);
    setErrorMessage(null);

    try {
      const results = await searchStreamingCatalog(backendUrl, authSession, trimmedQuery, {
        services: request.services,
        type: includeAllTypes ? 'all' : request.searchType,
        library: nextScope === 'library',
        limit: SEARCH_PAGE_SIZE,
        offset: page * SEARCH_PAGE_SIZE,
      });

      setTracks(results.tracks);
      setAlbums(results.albums);
      setPlaylists(results.playlists);
      setTotalResults(results.total);
      setResultMode(includeAllTypes ? 'all' : request.searchType);
      setCurrentPage(page);
      setHasSearched(true);
      setLastSearchRequest(request);
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : 'Music search failed unexpectedly.',
      );
    } finally {
      setIsSearching(false);
    }
  }

  async function handleSaveTrack(track: StreamingTrack) {
    if (!authSession) {
      showToast('Please log in before saving tracks.');
      return;
    }

    try {
      await saveTrackToLibrary(backendUrl, authSession, {
        track_id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration ?? 0,
        source: track.source,
        cover_url: track.cover_url,
      });
      showToast(`Added ${track.title} to your library.`);
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Failed to save track.');
    }
  }

  async function handleFavouriteTrack(track: StreamingTrack) {
    if (!authSession) {
      showToast('Please log in before hearting tracks.');
      return;
    }

    try {
      await addFavouriteStreamingTrack(backendUrl, authSession, {
        track_id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration ?? 0,
        source: track.source,
        cover_url: track.cover_url ?? undefined,
      });
      showToast(`Hearted ${track.title}.`);
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Failed to favourite track.');
    }
  }

  async function handlePlayTrack(track: StreamingTrack) {
    const playerKey = `${track.source}:${track.id}`;
    const isCurrentTrack = currentTrack?.key === playerKey;

    if (isCurrentTrack) {
      togglePlayPause();
      return;
    }

    if (track.source === 'spotify' && !track.stream_url) {
      showToast('Spotify playback is only available when a preview clip is provided for the track.');
      return;
    }

    if (!authSession) {
      showToast('Please log in before playing provider tracks.');
      return;
    }

    try {
      const trackUrl =
        track.source === 'tidal'
          ? ''
          : track.stream_url ??
            (await fetchTrackStreamUrl(backendUrl, authSession, track.id, track.source));

      playTrack({
        id: track.id,
        key: playerKey,
        title: track.title,
        artist: track.artist,
        album: track.album,
        artworkUrl: track.cover_url,
        duration: track.duration,
        source: track.source,
        url: trackUrl,
        backendUrl: track.source === 'tidal' ? backendUrl : undefined,
        sessionToken: track.source === 'tidal' ? authSession.sessionToken : undefined,
      });
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Failed to play track.');
    }
  }

  async function handleImportPlaylist(playlist: StreamingPlaylist, watched: boolean) {
    if (!authSession) {
      showToast('Please log in before saving playlists.');
      return;
    }

    try {
      await importProviderPlaylist(backendUrl, authSession, {
        source: playlist.source,
        playlist_id: playlist.id,
        name: playlist.name,
        description: playlist.description ?? null,
        owner: playlist.owner,
        cover_url: playlist.cover_url ?? null,
        is_public: playlist.is_public,
        watched,
      });

      showToast(
        watched
          ? `Imported ${playlist.name} as a watched playlist.`
          : `Cloned ${playlist.name} into your playlists.`,
      );
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Failed to save playlist.');
    }
  }

  const visibleResultCount = getVisibleResultCount(resultMode, tracks, albums, playlists);
  const totalPageCount = Math.max(1, Math.ceil(totalResults / SEARCH_PAGE_SIZE));
  const hasPreviousPage = currentPage > 0;
  const hasNextPage = currentPage + 1 < totalPageCount;

  if (!authSession) {
    return (
      <SafeAreaView className="flex-1 bg-slate-50 dark:bg-slate-950" edges={['left', 'right']}>
        <View className="flex-1 px-5 pb-6 pt-4">
          <Text className="text-sm leading-6 text-slate-600 dark:text-slate-400">
            Sign in first so the app can search connected providers, including your server music,
            and add tracks or import playlists into your library.
          </Text>

          <Pressable
            accessibilityRole="button"
            className="mt-4 rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
            onPress={() => {
              navigation.navigate('Login');
            }}
          >
            <Text className="text-center text-base font-semibold text-white">Go to login</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-slate-50 dark:bg-slate-950" edges={['left', 'right']}>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, paddingTop: 16 }}
        keyboardShouldPersistTaps="handled"
      >
        <View className="rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Search
          </Text>
          <TextInput
            autoCapitalize="none"
            autoCorrect={false}
            className="mt-4 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
            onChangeText={setQuery}
            onSubmitEditing={() => {
              void handleSearch();
            }}
            placeholder={searchPlaceholder}
            placeholderTextColor="#94a3b8"
            returnKeyType="search"
            value={query}
          />

          <View className="mt-4 gap-3">
            <View>
              <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400">
                Type
              </Text>
              <View className="mt-2 flex-row flex-wrap gap-2">
                <FilterChip isSelected={searchType === 'track'} label="Tracks" onPress={() => {
                  setSearchType('track');
                }} />
                <FilterChip isSelected={searchType === 'album'} label="Albums" onPress={() => {
                  setSearchType('album');
                }} />
                <FilterChip isSelected={searchType === 'playlist'} label="Playlists" onPress={() => {
                  setSearchType('playlist');
                }} />
              </View>
            </View>

            <View>
              <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400">
                Scope
              </Text>
              <View className="mt-2 flex-row flex-wrap gap-2">
                <FilterChip disabled={isServerOnlySelected} isSelected={searchScope === 'all'} label="Providers" onPress={() => {
                  setSearchScope('all');
                }} />
                <FilterChip disabled={isServerOnlySelected} isSelected={searchScope === 'library'} label="My Library" onPress={() => {
                  setSearchScope('library');
                }} />
              </View>
              {isServerOnlySelected ? (
                <Text className="mt-2 text-sm leading-6 text-slate-500 dark:text-slate-400">
                  Server search already targets your own music collection, so the scope filter is disabled.
                </Text>
              ) : null}
            </View>

            <View>
              <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400">
                Providers
              </Text>
              {providerFilterContent}
            </View>
          </View>

          <Pressable
            accessibilityRole="button"
            className="mt-4 rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
            disabled={isSearching || isBootstrapping}
            onPress={() => {
              void handleSearch(0);
            }}
          >
            {isSearching ? (
              <ActivityIndicator color="#ffffff" />
            ) : (
              <Text className="text-center text-base font-semibold text-white">Search providers</Text>
            )}
          </Pressable>

          {searchScope === 'library' || isServerOnlySelected ? (
            <Pressable
              accessibilityRole="button"
              className="mt-3 rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
              disabled={isSearching || isBootstrapping}
              onPress={() => {
                void handleSearch(0, {
                  allowEmptyQuery: true,
                  forceScope: isServerOnlySelected ? 'all' : 'library',
                  ignoreQuery: true,
                });
              }}
            >
              <Text className="text-center text-base font-semibold text-slate-700 dark:text-slate-200">
                {getSearchAllButtonLabel(searchType, searchScope, isServerOnlySelected)}
              </Text>
            </Pressable>
          ) : null}
        </View>

        {errorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm font-semibold text-rose-900">Browse failed</Text>
            <Text className="mt-1 text-sm text-rose-700">{errorMessage}</Text>
          </View>
        ) : null}

        {hasSearched ? (
          <View className="mt-4 rounded-[24px] border border-slate-200 bg-white px-4 py-4 dark:border-slate-800 dark:bg-slate-900">
            <View className="flex-row items-center justify-between gap-3">
              <Text className="text-sm font-medium text-slate-600 dark:text-slate-300">
                Page {currentPage + 1} / {totalPageCount}
              </Text>
              <View className="flex-row gap-3">
                <Pressable
                  accessibilityRole="button"
                  className="rounded-full border border-slate-200 bg-white px-4 py-2 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
                  disabled={!hasPreviousPage || isSearching}
                  onPress={() => {
                    void handleSearch(currentPage - 1);
                  }}
                >
                  <Text className="text-sm font-semibold text-slate-700 dark:text-slate-200">Previous</Text>
                </Pressable>
                <Pressable
                  accessibilityRole="button"
                  className="rounded-full border border-slate-200 bg-white px-4 py-2 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
                  disabled={!hasNextPage || isSearching}
                  onPress={() => {
                    void handleSearch(currentPage + 1);
                  }}
                >
                  <Text className="text-sm font-semibold text-slate-700 dark:text-slate-200">Next</Text>
                </Pressable>
              </View>
            </View>
          </View>
        ) : null}

        {resultMode === 'all' || resultMode === 'track' ? (
          <View className="mt-4">
            <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500 dark:text-slate-400">
              Tracks
            </Text>
            {tracks.length > 0 ? (
              <View className="mt-3">
                {tracks.map((track) => (
                  <BrowseTrackCard
                    isCurrentTrack={currentTrack?.key === `${track.source}:${track.id}`}
                    isPlaying={isPlaying}
                    key={`${track.source}:${track.id}`}
                    onFavourite={handleFavouriteTrack}
                    onPlay={handlePlayTrack}
                    onSave={handleSaveTrack}
                    track={track}
                  />
                ))}
              </View>
            ) : (
              <View className="mt-3 rounded-[24px] border border-dashed border-slate-300 bg-white px-4 py-5 dark:border-slate-700 dark:bg-slate-900">
                <Text className="text-sm leading-6 text-slate-600 dark:text-slate-400">
                  {getEmptyStateMessage({
                    isAllProvidersSelected,
                    isServerOnlySelected,
                    searchScope,
                    searchType: 'track',
                  })}
                </Text>
              </View>
            )}
          </View>
        ) : null}

        {resultMode === 'all' || resultMode === 'album' ? (
          <View className="mt-4">
            <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500 dark:text-slate-400">
              Albums
            </Text>
            {albums.length > 0 ? (
              <View className="mt-3">
                {albums.map((album) => (
                  <BrowseAlbumCard album={album} key={`${album.source}:${album.id}`} />
                ))}
              </View>
            ) : (
              <View className="mt-3 rounded-[24px] border border-dashed border-slate-300 bg-white px-4 py-5 dark:border-slate-700 dark:bg-slate-900">
                <Text className="text-sm leading-6 text-slate-600 dark:text-slate-400">
                  {getEmptyStateMessage({
                    isAllProvidersSelected,
                    isServerOnlySelected,
                    searchScope,
                    searchType: 'album',
                  })}
                </Text>
              </View>
            )}
          </View>
        ) : null}

        {resultMode === 'all' || resultMode === 'playlist' ? (
          <View className="mt-4">
            <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500 dark:text-slate-400">
              Playlists
            </Text>
            {playlists.length > 0 ? (
              <View className="mt-3">
                {playlists.map((playlist) => (
                  <BrowsePlaylistCard
                    authSession={authSession}
                    backendUrl={backendUrl}
                    key={`${playlist.source}:${playlist.id}`}
                    onClone={(selectedPlaylist) => {
                      void handleImportPlaylist(selectedPlaylist, false);
                    }}
                    onWatch={(selectedPlaylist) => {
                      void handleImportPlaylist(selectedPlaylist, true);
                    }}
                    playlist={playlist}
                  />
                ))}
              </View>
            ) : (
              <View className="mt-3 rounded-[24px] border border-dashed border-slate-300 bg-white px-4 py-5 dark:border-slate-700 dark:bg-slate-900">
                <Text className="text-sm leading-6 text-slate-600 dark:text-slate-400">
                  {getEmptyStateMessage({
                    isAllProvidersSelected,
                    isServerOnlySelected,
                    searchScope,
                    searchType: 'playlist',
                  })}
                </Text>
              </View>
            )}
          </View>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}