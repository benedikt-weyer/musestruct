import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { usePlayer } from '../context/PlayerContext';
import { PLAYABLE_AUDIO_EXTENSIONS } from '../constants/audio';
import { useSettings } from '../context/SettingsContext';
import { MusicFolderAccess } from '../native/MusicFolderAccess';
import type { MusicFile } from '../types/music';

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

export function HomeScreen() {
  const { selectedFolder } = useSettings();
  const { currentTrack, isPlaying, playTrack, togglePlayPause } = usePlayer();
  const [files, setFiles] = useState<MusicFile[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const hasSelectedFolder = selectedFolder !== null;
  const folderContent = hasSelectedFolder ? (
    <FlatList
      className="mt-4"
      contentContainerStyle={{ paddingBottom: 24 }}
      data={files}
      keyExtractor={(item) => item.id}
      refreshControl={<RefreshControl refreshing={isLoading} onRefresh={() => void loadFiles()} />}
      ListEmptyComponent={
        isLoading ? (
          <View className="items-center justify-center py-16">
            <ActivityIndicator color="#0f766e" size="large" />
            <Text className="mt-4 text-sm text-slate-600 dark:text-slate-400">Scanning folders recursively…</Text>
          </View>
        ) : (
          <View className="rounded-[24px] border border-dashed border-slate-300 bg-white px-4 py-6 dark:border-slate-700 dark:bg-slate-900">
            <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">
              No playable files found
            </Text>
            <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
              The selected folder does not contain any supported audio files yet.
            </Text>
          </View>
        )
      }
      renderItem={({ item }) => {
        const playerKey = `device:${item.id}`;
        const isCurrentTrack = currentTrack?.key === playerKey;

        return (
        <View className="mb-3 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <View className="flex-row items-start justify-between gap-3">
            <View className="flex-1">
              <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">{item.name}</Text>
              <Text className="mt-1 text-sm text-slate-500 dark:text-slate-400">{item.pathLabel}</Text>
            </View>
            <View className="rounded-full bg-teal-100 px-3 py-1 dark:bg-teal-950/60">
              <Text className="text-xs font-semibold uppercase tracking-[1px] text-teal-700">
                {item.extension}
              </Text>
            </View>
          </View>
          <View className="mt-4 flex-row justify-between">
            <Text className="text-xs font-medium uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              {formatFileSize(item.size)}
            </Text>
            <Text className="text-xs font-medium uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
              {formatModifiedAt(item.modifiedAt)}
            </Text>
          </View>

          <Pressable
            accessibilityRole="button"
            className="mt-4 rounded-full border border-slate-200 bg-white px-4 py-3 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
            onPress={() => {
              if (isCurrentTrack) {
                togglePlayPause();
                return;
              }

              playTrack({
                id: item.id,
                key: playerKey,
                title: item.name,
                artist: 'Local file',
                album: selectedFolder?.name,
                description: item.pathLabel,
                duration: undefined,
                source: 'device',
                url: item.uri,
              });
            }}
          >
            <Text className="text-center text-sm font-semibold text-slate-700 dark:text-slate-200">
              {isCurrentTrack && isPlaying ? 'Pause track' : isCurrentTrack ? 'Resume track' : 'Play track'}
            </Text>
          </Pressable>
        </View>
      );
      }}
    />
  ) : (
    <View className="mt-4 rounded-[24px] border border-dashed border-slate-300 bg-white px-4 py-6 dark:border-slate-700 dark:bg-slate-900">
      <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">No folder selected yet</Text>
      <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
        Move to the Settings tab and choose a folder from your device. The app will scan it
        recursively for {PLAYABLE_AUDIO_EXTENSIONS.join(', ')} files.
      </Text>
    </View>
  );

  async function loadFiles() {
    if (!selectedFolder) {
      setFiles([]);
      setErrorMessage(null);
      return;
    }

    setIsLoading(true);
    setErrorMessage(null);

    try {
      const nextFiles = await MusicFolderAccess.listPlayableFiles(
        selectedFolder.id,
        [...PLAYABLE_AUDIO_EXTENSIONS],
      );
      setFiles(nextFiles);
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : 'The selected folder could not be scanned.',
      );
      setFiles([]);
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    void loadFiles();
  }, [selectedFolder?.id]);

  return (
    <SafeAreaView className="flex-1 bg-slate-50 dark:bg-slate-950" edges={["left", "right"]}>
      <View className="flex-1 px-5 pb-6 pt-4">
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500 dark:text-slate-400">
            Home
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900 dark:text-slate-100">
            Music Library
          </Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-400">
            {selectedFolder
              ? `Showing playable files from ${selectedFolder.name}.`
              : 'Select a music folder in Settings to start scanning your files.'}
          </Text>
        </View>

        {selectedFolder ? (
          <View className="mt-4 rounded-[24px] border border-slate-200 bg-white px-4 py-4 dark:border-slate-800 dark:bg-slate-900">
            <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
              Selected Folder
            </Text>
            <Text className="mt-2 text-lg font-semibold text-slate-900 dark:text-slate-100">
              {selectedFolder.name}
            </Text>
            <Text className="mt-1 text-sm text-slate-500 dark:text-slate-400">{selectedFolder.pathLabel}</Text>
            <View className="mt-4 flex-row items-center justify-between">
              <Text className="text-sm text-slate-600 dark:text-slate-400">{files.length} playable files found</Text>
              <Pressable
                accessibilityRole="button"
                className="rounded-full bg-slate-900 px-4 py-2 active:bg-slate-700"
                onPress={() => {
                  void loadFiles();
                }}
              >
                <Text className="text-sm font-semibold text-white">Refresh</Text>
              </Pressable>
            </View>
          </View>
        ) : null}

        {errorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm font-semibold text-rose-900">Folder scan failed</Text>
            <Text className="mt-1 text-sm text-rose-700">{errorMessage}</Text>
          </View>
        ) : null}

        {folderContent}
      </View>
    </SafeAreaView>
  );
}