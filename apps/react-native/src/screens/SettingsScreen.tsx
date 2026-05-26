import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { PLAYABLE_AUDIO_EXTENSIONS } from '../constants/audio';
import { useSettings } from '../context/SettingsContext';
import { MusicFolderAccess } from '../native/MusicFolderAccess';

type NativeError = Error & {
  code?: string;
};

function isCancelled(error: unknown) {
  return (error as NativeError | undefined)?.code === 'E_PICK_CANCELLED';
}

export function SettingsScreen() {
  const { selectedFolder, setSelectedFolder } = useSettings();
  const [isPickingFolder, setIsPickingFolder] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  let folderButtonLabel = 'Choose music folder';

  if (isPickingFolder) {
    folderButtonLabel = 'Opening folder picker…';
  } else if (selectedFolder) {
    folderButtonLabel = 'Change music folder';
  }

  async function handleSelectFolder() {
    setIsPickingFolder(true);
    setErrorMessage(null);

    try {
      const folder = await MusicFolderAccess.pickFolder();
      setSelectedFolder(folder);
    } catch (error) {
      if (!isCancelled(error)) {
        setErrorMessage(
          error instanceof Error
            ? error.message
            : 'The folder picker could not be opened on this device.',
        );
      }
    } finally {
      setIsPickingFolder(false);
    }
  }

  return (
    <SafeAreaView className="flex-1 bg-slate-50" edges={["left", "right"]}>
      <View className="flex-1 px-5 pb-6 pt-4">
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500">
            Settings
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900">
            Music Source
          </Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600">
            Choose the folder that should be scanned recursively for playable audio files.
            Your choice is stored locally with MMKV so it survives app restarts.
          </Text>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Folder Access
          </Text>
          {selectedFolder ? (
            <>
              <Text className="mt-2 text-lg font-semibold text-slate-900">
                {selectedFolder.name}
              </Text>
              <Text className="mt-1 text-sm leading-6 text-slate-500">
                {selectedFolder.pathLabel}
              </Text>
            </>
          ) : (
            <Text className="mt-2 text-sm leading-6 text-slate-600">
              No folder has been selected yet.
            </Text>
          )}

          <View className="mt-5 gap-3">
            <Pressable
              accessibilityRole="button"
              className="rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
              disabled={isPickingFolder}
              onPress={() => {
                void handleSelectFolder();
              }}
            >
              <Text className="text-center text-base font-semibold text-white">
                {folderButtonLabel}
              </Text>
            </Pressable>

            {selectedFolder ? (
              <Pressable
                accessibilityRole="button"
                className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100"
                onPress={() => {
                  setSelectedFolder(null);
                  setErrorMessage(null);
                }}
              >
                <Text className="text-center text-base font-semibold text-slate-700">
                  Clear selection
                </Text>
              </Pressable>
            ) : null}
          </View>
        </View>

        <View className="mt-4 rounded-[24px] border border-slate-200 bg-white px-4 py-4">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500">
            Supported Formats
          </Text>
          <Text className="mt-2 text-sm leading-6 text-slate-600">
            Files are treated as playable when their extension matches:
          </Text>
          <View className="mt-3 flex-row flex-wrap gap-2">
            {PLAYABLE_AUDIO_EXTENSIONS.map((extension) => (
              <View key={extension} className="rounded-full bg-slate-100 px-3 py-2">
                <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-700">
                  {extension}
                </Text>
              </View>
            ))}
          </View>
        </View>

        {errorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm font-semibold text-rose-900">Folder selection failed</Text>
            <Text className="mt-1 text-sm text-rose-700">{errorMessage}</Text>
          </View>
        ) : null}
      </View>
    </SafeAreaView>
  );
}