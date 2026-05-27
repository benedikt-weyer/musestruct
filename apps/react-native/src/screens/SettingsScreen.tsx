import { useEffect, useState } from 'react';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  ToastAndroid,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { PLAYABLE_AUDIO_EXTENSIONS } from '../constants/audio';
import { LOCAL_BACKEND_URL, REMOTE_BACKEND_URL } from '../constants/backend';
import { useSettings } from '../context/SettingsContext';
import type { RootStackParamList } from '../navigation/types';
import { MusicFolderAccess } from '../native/MusicFolderAccess';
import { normalizeBackendUrl, testBackendConnection } from '../services/backendApi';

type NativeError = Error & {
  code?: string;
};

function isCancelled(error: unknown) {
  return (error as NativeError | undefined)?.code === 'E_PICK_CANCELLED';
}

function showConnectionToast(message: string, isError: boolean) {
  if (Platform.OS === 'android') {
    ToastAndroid.show(message, ToastAndroid.SHORT);
    return;
  }

  Alert.alert(isError ? 'Connection failed' : 'Connection successful', message);
}

export function SettingsScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const {
    selectedFolder,
    setSelectedFolder,
    backendUrl,
    setBackendUrl,
    authSession,
    setAuthSession,
  } = useSettings();
  const [isPickingFolder, setIsPickingFolder] = useState(false);
  const [folderErrorMessage, setFolderErrorMessage] = useState<string | null>(null);
  const [backendUrlInput, setBackendUrlInput] = useState(backendUrl);
  const [connectionMessage, setConnectionMessage] = useState<string | null>(null);
  const [connectionTone, setConnectionTone] = useState<'success' | 'error' | null>(null);
  const [isTestingConnection, setIsTestingConnection] = useState(false);
  let folderButtonLabel = 'Choose music folder';

  useEffect(() => {
    setBackendUrlInput(backendUrl);
  }, [backendUrl]);

  if (isPickingFolder) {
    folderButtonLabel = 'Opening folder picker…';
  } else if (selectedFolder) {
    folderButtonLabel = 'Change music folder';
  }

  async function handleSelectFolder() {
    setIsPickingFolder(true);
    setFolderErrorMessage(null);

    try {
      const folder = await MusicFolderAccess.pickFolder();
      setSelectedFolder(folder);
    } catch (error) {
      if (!isCancelled(error)) {
        setFolderErrorMessage(
          error instanceof Error
            ? error.message
            : 'The folder picker could not be opened on this device.',
        );
      }
    } finally {
      setIsPickingFolder(false);
    }
  }

  function saveBackendUrl(nextBackendUrl: string) {
    const normalizedUrl = normalizeBackendUrl(nextBackendUrl);

    if (!normalizedUrl) {
      setConnectionTone('error');
      setConnectionMessage('Please enter a backend URL before saving it.');
      return;
    }

    if (normalizedUrl !== normalizeBackendUrl(backendUrl)) {
      setAuthSession(null);
    }

    setBackendUrl(normalizedUrl);
    setBackendUrlInput(normalizedUrl);
    setConnectionTone('success');
    setConnectionMessage('Backend URL saved.');
  }

  async function handleTestConnection() {
    setIsTestingConnection(true);

    try {
      const result = await testBackendConnection(backendUrlInput);
      showConnectionToast(result.message, false);
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'The backend connection test failed.';
      showConnectionToast(message, true);
    } finally {
      setIsTestingConnection(false);
    }
  }

  const connectionContainerClassName =
    connectionTone === 'error'
      ? 'mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4'
      : 'mt-4 rounded-[24px] border border-teal-200 bg-teal-50 px-4 py-4';
  const connectionTitleClassName =
    connectionTone === 'error'
      ? 'text-sm font-semibold text-rose-900'
      : 'text-sm font-semibold text-teal-900';
  const connectionMessageClassName =
    connectionTone === 'error' ? 'mt-1 text-sm text-rose-700' : 'mt-1 text-sm text-teal-700';

  return (
    <SafeAreaView className="flex-1 bg-slate-50" edges={["left", "right"]}>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, paddingTop: 16 }}
        keyboardShouldPersistTaps="handled"
      >
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500">
            Settings
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900">
            App Settings
          </Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600">
            Configure the backend connection, manage your account, and choose the local folder
            that should be scanned recursively for playable audio files.
          </Text>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Backend
          </Text>
          <Text className="mt-2 text-sm leading-6 text-slate-600">
            Choose a quick preset or enter a custom backend URL.
          </Text>

          <TextInput
            autoCapitalize="none"
            autoCorrect={false}
            className="mt-4 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900"
            keyboardType="url"
            onChangeText={setBackendUrlInput}
            placeholder="https://your-backend.example"
            placeholderTextColor="#94a3b8"
            value={backendUrlInput}
          />

          <View className="mt-4 gap-3">
            <Pressable
              accessibilityRole="button"
              className="rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
              onPress={() => {
                saveBackendUrl(LOCAL_BACKEND_URL);
              }}
            >
              <Text className="text-center text-base font-semibold text-white">
                Use local backend
              </Text>
            </Pressable>

            <Pressable
              accessibilityRole="button"
              className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100"
              onPress={() => {
                saveBackendUrl(REMOTE_BACKEND_URL);
              }}
            >
              <Text className="text-center text-base font-semibold text-slate-700">
                Use hosted backend
              </Text>
            </Pressable>

            <Pressable
              accessibilityRole="button"
              className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100"
              onPress={() => {
                saveBackendUrl(backendUrlInput);
              }}
            >
              <Text className="text-center text-base font-semibold text-slate-700">
                Save custom URL
              </Text>
            </Pressable>

            <Pressable
              accessibilityRole="button"
              className="rounded-full border border-teal-200 bg-teal-50 px-5 py-4 active:bg-teal-100"
              disabled={isTestingConnection}
              onPress={() => {
                void handleTestConnection();
              }}
            >
              {isTestingConnection ? (
                <ActivityIndicator color="#0f766e" />
              ) : (
                <Text className="text-center text-base font-semibold text-teal-700">
                  Test connection
                </Text>
              )}
            </Pressable>
          </View>

          <Text className="mt-4 text-xs font-semibold uppercase tracking-[1px] text-slate-400">
            Saved backend
          </Text>
          <Text className="mt-1 text-sm leading-6 text-slate-600">{backendUrl}</Text>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Account
          </Text>
          {authSession ? (
            <>
              <Text className="mt-2 text-lg font-semibold text-slate-900">
                {authSession.user.username}
              </Text>
              <Text className="mt-1 text-sm leading-6 text-slate-500">
                {authSession.user.email}
              </Text>
            </>
          ) : (
            <Text className="mt-2 text-sm leading-6 text-slate-600">
              No backend session is stored yet.
            </Text>
          )}

          <View className="mt-5 gap-3">
            <Pressable
              accessibilityRole="button"
              className="rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
              onPress={() => {
                navigation.navigate('Login');
              }}
            >
              <Text className="text-center text-base font-semibold text-white">Login</Text>
            </Pressable>

            <Pressable
              accessibilityRole="button"
              className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100"
              onPress={() => {
                navigation.navigate('Register');
              }}
            >
              <Text className="text-center text-base font-semibold text-slate-700">
                Register
              </Text>
            </Pressable>

            {authSession ? (
              <Pressable
                accessibilityRole="button"
                className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100"
                onPress={() => {
                  setAuthSession(null);
                  setConnectionTone('success');
                  setConnectionMessage('Stored session cleared.');
                }}
              >
                <Text className="text-center text-base font-semibold text-slate-700">
                  Clear saved session
                </Text>
              </Pressable>
            ) : null}
          </View>
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
                  setFolderErrorMessage(null);
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

        {connectionMessage ? (
          <View className={connectionContainerClassName}>
            <Text className={connectionTitleClassName}>
              {connectionTone === 'error' ? 'Connection failed' : 'Connection status'}
            </Text>
            <Text className={connectionMessageClassName}>{connectionMessage}</Text>
          </View>
        ) : null}

        {folderErrorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm font-semibold text-rose-900">Folder selection failed</Text>
            <Text className="mt-1 text-sm text-rose-700">{folderErrorMessage}</Text>
          </View>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}