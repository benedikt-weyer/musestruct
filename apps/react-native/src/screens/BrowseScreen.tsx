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

import { usePlayer } from '../context/PlayerContext';
import { useSettings } from '../context/SettingsContext';
import type { RootStackParamList } from '../navigation/types';
import {
  fetchAvailableServices,
  fetchServiceStatus,
  fetchTrackStreamUrl,
  saveAlbumToLibrary,
  saveTrackToLibrary,
  searchStreamingCatalog,
} from '../services/streamingLibraryApi';
import type {
  AvailableService,
  ConnectedServiceInfo,
  StreamingAlbum,
  StreamingTrack,
} from '../types/streaming';

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

function BrowseTrackCard({
  isCurrentTrack,
  isPlaying,
  onPlay,
  onSave,
  track,
}: Readonly<{
  isCurrentTrack: boolean;
  isPlaying: boolean;
  onPlay: (track: StreamingTrack) => void;
  onSave: (track: StreamingTrack) => void;
  track: StreamingTrack;
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
          <Text className="text-base font-semibold text-slate-900">{track.title}</Text>
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
          <Text className="text-center text-sm font-semibold text-white">
            {isCurrentTrack && isPlaying ? 'Pause track' : isCurrentTrack ? 'Resume track' : 'Play track'}
          </Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="flex-1 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100"
          onPress={() => {
            onSave(track);
          }}
        >
          <Text className="text-center text-sm font-semibold text-slate-700">Add track to library</Text>
        </Pressable>
      </View>
    </View>
  );
}

function BrowseAlbumCard({
  album,
  onSave,
}: Readonly<{
  album: StreamingAlbum;
  onSave: (album: StreamingAlbum) => void;
}>) {
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
            {album.release_date ?? 'Unknown release'}
          </Text>
          <Text className="mt-2 text-xs font-semibold uppercase tracking-[1px] text-slate-400">
            {album.source} • {album.tracks.length} tracks
          </Text>
        </View>
      </View>

      <Pressable
        accessibilityRole="button"
        className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100"
        onPress={() => {
          onSave(album);
        }}
      >
        <Text className="text-center text-sm font-semibold text-slate-700">Add album to library</Text>
      </Pressable>
    </View>
  );
}

export function BrowseScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { authSession, backendUrl } = useSettings();
  const { currentTrack, isPlaying, playTrack, togglePlayPause } = usePlayer();
  const [query, setQuery] = useState('');
  const [availableServices, setAvailableServices] = useState<AvailableService[]>([]);
  const [serviceStatus, setServiceStatus] = useState<ConnectedServiceInfo[]>([]);
  const [selectedServices, setSelectedServices] = useState<string[]>([]);
  const [tracks, setTracks] = useState<StreamingTrack[]>([]);
  const [albums, setAlbums] = useState<StreamingAlbum[]>([]);
  const [isBootstrapping, setIsBootstrapping] = useState(false);
  const [isSearching, setIsSearching] = useState(false);
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

        const externalServices = available.services.filter((service) => service.name !== 'server');
        const connectedExternalServiceNames = status.services
          .filter((service) => service.is_connected && service.name !== 'server')
          .map((service) => service.name);

        setAvailableServices(externalServices);
        setServiceStatus(status.services.filter((service) => service.name !== 'server'));
        setSelectedServices(connectedExternalServiceNames);
      } catch (error) {
        setErrorMessage(
          error instanceof Error
            ? error.message
            : 'Failed to load connected music providers.',
        );
      } finally {
        setIsBootstrapping(false);
      }
    }

    void loadServices();
  }, [authSession, backendUrl]);

  const connectedServices = useMemo(
    () => serviceStatus.filter((service) => service.is_connected),
    [serviceStatus],
  );
  let connectedProvidersContent = (
    <Text className="mt-3 text-sm leading-6 text-slate-600">
      No external providers are currently connected for this account.
    </Text>
  );

  if (isBootstrapping) {
    connectedProvidersContent = (
      <View className="py-6">
        <ActivityIndicator color="#0f766e" />
      </View>
    );
  } else if (connectedServices.length > 0) {
    connectedProvidersContent = (
      <View className="mt-3 gap-3">
        {connectedServices.map((service) => (
          <View key={service.name} className="rounded-[18px] bg-slate-50 px-4 py-3">
            <Text className="text-sm font-semibold text-slate-900">{service.display_name}</Text>
            <Text className="mt-1 text-sm text-slate-600">
              {service.account_username ?? 'Connected'}
            </Text>
          </View>
        ))}
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

  async function handleSearch() {
    if (!authSession) {
      setErrorMessage('Please log in before browsing external providers.');
      return;
    }

    const trimmedQuery = query.trim();
    if (!trimmedQuery) {
      setErrorMessage('Enter a search term first.');
      return;
    }

    if (selectedServices.length === 0) {
      setErrorMessage('Select at least one connected provider to search.');
      return;
    }

    setIsSearching(true);
    setErrorMessage(null);

    try {
      const results = await searchStreamingCatalog(backendUrl, authSession, trimmedQuery, {
        services: selectedServices,
        limit: 20,
      });

      setTracks(results.tracks);
      setAlbums(results.albums);
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

  async function handlePlayTrack(track: StreamingTrack) {
    const playerKey = `${track.source}:${track.id}`;
    const isCurrentTrack = currentTrack?.key === playerKey;

    if (isCurrentTrack) {
      togglePlayPause();
      return;
    }

    if (!authSession) {
      showToast('Please log in before playing provider tracks.');
      return;
    }

    try {
      const streamUrl = track.stream_url
        ? track.stream_url
        : await fetchTrackStreamUrl(backendUrl, authSession, track.id, track.source);

      playTrack({
        id: track.id,
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
      showToast(error instanceof Error ? error.message : 'Failed to play track.');
    }
  }

  async function handleSaveAlbum(album: StreamingAlbum) {
    if (!authSession) {
      showToast('Please log in before saving albums.');
      return;
    }

    try {
      await saveAlbumToLibrary(backendUrl, authSession, {
        album_id: album.id,
        title: album.title,
        artist: album.artist,
        release_date: album.release_date,
        cover_url: album.cover_url,
        source: album.source,
        track_count: album.tracks.length,
      });
      showToast(`Added ${album.title} to your library.`);
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Failed to save album.');
    }
  }

  if (!authSession) {
    return (
      <SafeAreaView className="flex-1 bg-slate-50" edges={['left', 'right']}>
        <View className="flex-1 px-5 pb-6 pt-4">
          <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200">
            <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500">
              Browse
            </Text>
            <Text className="mt-2 text-3xl font-bold text-slate-900">External Providers</Text>
            <Text className="mt-3 text-sm leading-6 text-slate-600">
              Sign in first so the app can search connected providers and add tracks or albums to
              your library.
            </Text>
          </View>

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
    <SafeAreaView className="flex-1 bg-slate-50" edges={['left', 'right']}>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, paddingTop: 16 }}
        keyboardShouldPersistTaps="handled"
      >
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500">
            Browse
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900">External Providers</Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600">
            Search connected providers and add tracks or albums to your personal library.
          </Text>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Search
          </Text>
          <TextInput
            autoCapitalize="none"
            autoCorrect={false}
            className="mt-4 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900"
            onChangeText={setQuery}
            onSubmitEditing={() => {
              void handleSearch();
            }}
            placeholder="Search tracks and albums"
            placeholderTextColor="#94a3b8"
            returnKeyType="search"
            value={query}
          />

          <View className="mt-4 flex-row flex-wrap gap-2">
            {availableServices.map((service) => {
              const status = serviceStatus.find((entry) => entry.name === service.name);
              const isSelected = selectedServices.includes(service.name);
              const isConnected = status?.is_connected === true;
              const chipClassName = isSelected
                ? 'rounded-full border border-teal-200 bg-teal-50 px-3 py-2'
                : 'rounded-full border border-slate-200 bg-white px-3 py-2';
              const textClassName = isSelected
                ? 'text-xs font-semibold uppercase tracking-[1px] text-teal-700'
                : 'text-xs font-semibold uppercase tracking-[1px] text-slate-700';

              return (
                <Pressable
                  key={service.name}
                  accessibilityRole="button"
                  className={chipClassName}
                  disabled={!isConnected}
                  onPress={() => {
                    toggleService(service.name);
                  }}
                >
                  <Text className={textClassName}>
                    {service.display_name} {isConnected ? '' : 'offline'}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          <Pressable
            accessibilityRole="button"
            className="mt-4 rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
            disabled={isSearching || isBootstrapping}
            onPress={() => {
              void handleSearch();
            }}
          >
            {isSearching ? (
              <ActivityIndicator color="#ffffff" />
            ) : (
              <Text className="text-center text-base font-semibold text-white">Search providers</Text>
            )}
          </Pressable>
        </View>

        <View className="mt-4 rounded-[24px] border border-slate-200 bg-white px-4 py-4">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500">
            Connected Providers
          </Text>
          {connectedProvidersContent}
        </View>

        {errorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm font-semibold text-rose-900">Browse failed</Text>
            <Text className="mt-1 text-sm text-rose-700">{errorMessage}</Text>
          </View>
        ) : null}

        <View className="mt-4">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500">
            Tracks
          </Text>
          {tracks.length > 0 ? (
            <View className="mt-3">
              {tracks.map((track) => (
                <BrowseTrackCard
                  isCurrentTrack={currentTrack?.key === `${track.source}:${track.id}`}
                  isPlaying={isPlaying}
                  key={`${track.source}:${track.id}`}
                  onPlay={handlePlayTrack}
                  onSave={handleSaveTrack}
                  track={track}
                />
              ))}
            </View>
          ) : (
            <View className="mt-3 rounded-[24px] border border-dashed border-slate-300 bg-white px-4 py-5">
              <Text className="text-sm leading-6 text-slate-600">
                Search a connected provider to see matching tracks.
              </Text>
            </View>
          )}
        </View>

        <View className="mt-4">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500">
            Albums
          </Text>
          {albums.length > 0 ? (
            <View className="mt-3">
              {albums.map((album) => (
                <BrowseAlbumCard album={album} key={`${album.source}:${album.id}`} onSave={handleSaveAlbum} />
              ))}
            </View>
          ) : (
            <View className="mt-3 rounded-[24px] border border-dashed border-slate-300 bg-white px-4 py-5">
              <Text className="text-sm leading-6 text-slate-600">
                Search a connected provider to see matching albums.
              </Text>
            </View>
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}