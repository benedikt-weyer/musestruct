import { useEffect, useRef, useState } from 'react';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
  ActivityIndicator,
  Alert,
  Linking,
  Platform,
  Pressable,
  ScrollView,
  Switch,
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
import {
  connectQobuzProvider,
  disconnectStreamingProvider,
  fetchServerPreloadStatus,
  fetchServiceStatus,
  fetchSpotifyAuthUrl,
  fetchTidalAuthUrl,
  startServerPreload,
} from '../services/streamingLibraryApi';
import type { AuthSession } from '../types/auth';
import type {
  ConnectedServiceInfo,
  ServerPreloadMode,
  ServerPreloadProgress,
} from '../types/streaming';

const SPOTIFY_APP_REDIRECT_URL = 'musestruct://spotify';
const TIDAL_APP_REDIRECT_URL = 'musestruct://tidal';

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

function getFolderButtonLabel(isPickingFolder: boolean, selectedFolder: unknown) {
  if (isPickingFolder) {
    return 'Opening folder picker…';
  }

  if (selectedFolder) {
    return 'Change music folder';
  }

  return 'Choose music folder';
}

type ProviderActionButtonProps = {
  busy: boolean;
  label: string;
  onPress: () => void;
  tone: 'primary' | 'secondary';
};

function ProviderActionButton({ busy, label, onPress, tone }: Readonly<ProviderActionButtonProps>) {
  const buttonClassName =
    tone === 'primary'
      ? 'mt-4 rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700'
      : 'mt-4 rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-900 dark:active:bg-slate-800';
  const textClassName =
    tone === 'primary'
      ? 'text-center text-base font-semibold text-white'
      : 'text-center text-base font-semibold text-slate-700 dark:text-slate-200';
  const indicatorColor = tone === 'primary' ? '#ffffff' : '#0f766e';

  return (
    <Pressable accessibilityRole="button" className={buttonClassName} disabled={busy} onPress={onPress}>
      {busy ? (
        <ActivityIndicator color={indicatorColor} />
      ) : (
        <Text className={textClassName}>{label}</Text>
      )}
    </Pressable>
  );
}

type QobuzProviderCardProps = {
  busyConnecting: boolean;
  busyDisconnecting: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
  onPasswordChange: (value: string) => void;
  onUsernameChange: (value: string) => void;
  password: string;
  provider: ConnectedServiceInfo | null;
  username: string;
};

function QobuzProviderCard({
  busyConnecting,
  busyDisconnecting,
  onConnect,
  onDisconnect,
  onPasswordChange,
  onUsernameChange,
  password,
  provider,
  username,
}: Readonly<QobuzProviderCardProps>) {
  const isConnected = provider?.is_connected === true;
  const description = isConnected
    ? provider?.account_username ?? 'Connected'
    : 'Connect with your Qobuz account credentials.';

  return (
    <View className="mt-4 rounded-[20px] border border-slate-200 bg-slate-50 px-4 py-4 dark:border-slate-700 dark:bg-slate-950">
      <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">Qobuz</Text>
      <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">{description}</Text>

      {isConnected ? (
        <ProviderActionButton
          busy={busyDisconnecting}
          label="Disconnect Qobuz"
          onPress={onDisconnect}
          tone="secondary"
        />
      ) : (
        <>
          <TextInput
            autoCapitalize="none"
            autoComplete="username"
            autoCorrect={false}
            className="mt-4 rounded-[18px] border border-slate-200 bg-white px-4 py-3 text-base text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100"
            importantForAutofill="yes"
            onChangeText={onUsernameChange}
            placeholder="Qobuz username"
            placeholderTextColor="#94a3b8"
            textContentType="username"
            value={username}
          />
          <TextInput
            autoCapitalize="none"
            autoComplete="current-password"
            autoCorrect={false}
            className="mt-3 rounded-[18px] border border-slate-200 bg-white px-4 py-3 text-base text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100"
            importantForAutofill="yes"
            onChangeText={onPasswordChange}
            placeholder="Qobuz password"
            placeholderTextColor="#94a3b8"
            secureTextEntry
            textContentType="password"
            value={password}
          />
          <ProviderActionButton
            busy={busyConnecting}
            label="Connect Qobuz"
            onPress={onConnect}
            tone="primary"
          />
        </>
      )}
    </View>
  );
}

type SpotifyProviderCardProps = {
  busyConnecting: boolean;
  busyDisconnecting: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
  provider: ConnectedServiceInfo | null;
};

function SpotifyProviderCard({
  busyConnecting,
  busyDisconnecting,
  onConnect,
  onDisconnect,
  provider,
}: Readonly<SpotifyProviderCardProps>) {
  const isConnected = provider?.is_connected === true;
  const description = isConnected
    ? provider?.account_username ?? 'Connected'
    : 'Open Spotify authorization in your browser, then return here and refresh status.';

  return (
    <View className="mt-4 rounded-[20px] border border-slate-200 bg-slate-50 px-4 py-4 dark:border-slate-700 dark:bg-slate-950">
      <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">Spotify</Text>
      <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">{description}</Text>

      {isConnected ? (
        <ProviderActionButton
          busy={busyDisconnecting}
          label="Disconnect Spotify"
          onPress={onDisconnect}
          tone="secondary"
        />
      ) : (
        <ProviderActionButton
          busy={busyConnecting}
          label="Connect Spotify"
          onPress={onConnect}
          tone="primary"
        />
      )}
    </View>
  );
}

type TidalProviderCardProps = {
  busyConnecting: boolean;
  busyDisconnecting: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
  provider: ConnectedServiceInfo | null;
};

function TidalProviderCard({
  busyConnecting,
  busyDisconnecting,
  onConnect,
  onDisconnect,
  provider,
}: Readonly<TidalProviderCardProps>) {
  const isConnected = provider?.is_connected === true;
  const description = isConnected
    ? provider?.account_username ?? 'Connected'
    : 'Open Tidal authorization in your browser, then return here and refresh status.';

  return (
    <View className="mt-4 rounded-[20px] border border-slate-200 bg-slate-50 px-4 py-4 dark:border-slate-700 dark:bg-slate-950">
      <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">Tidal</Text>
      <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">{description}</Text>

      {isConnected ? (
        <ProviderActionButton
          busy={busyDisconnecting}
          label="Disconnect Tidal"
          onPress={onDisconnect}
          tone="secondary"
        />
      ) : (
        <ProviderActionButton
          busy={busyConnecting}
          label="Connect Tidal"
          onPress={onConnect}
          tone="primary"
        />
      )}
    </View>
  );
}

type ProviderSettingsCardProps = {
  authSession: AuthSession | null;
  backendUrl: string;
};

function ProviderSettingsCard({ authSession, backendUrl }: Readonly<ProviderSettingsCardProps>) {
  const [providerStatus, setProviderStatus] = useState<ConnectedServiceInfo[]>([]);
  const [providerErrorMessage, setProviderErrorMessage] = useState<string | null>(null);
  const [qobuzUsername, setQobuzUsername] = useState('');
  const [qobuzPassword, setQobuzPassword] = useState('');
  const [providerAction, setProviderAction] = useState<string | null>(null);
  const lastHandledProviderUrlRef = useRef<string | null>(null);

  useEffect(() => {
    if (!authSession) {
      setProviderStatus([]);
      setProviderErrorMessage(null);
      return;
    }

    void loadProviderStatus();
  }, [authSession, backendUrl]);

  useEffect(() => {
    async function handleProviderRedirect(url: string | null) {
      if (!url || lastHandledProviderUrlRef.current === url) {
        return;
      }

      let parsedUrl: URL;

      try {
        parsedUrl = new URL(url);
      } catch {
        return;
      }

      if (parsedUrl.protocol !== 'musestruct:') {
        return;
      }

      const providerName = parsedUrl.hostname;

      if (providerName !== 'spotify' && providerName !== 'tidal') {
        return;
      }

      lastHandledProviderUrlRef.current = url;
      const status = parsedUrl.searchParams.get('status');
      const message = parsedUrl.searchParams.get('message');
      const providerLabel = providerName === 'tidal' ? 'Tidal' : 'Spotify';

      if (status === 'success') {
        await loadProviderStatus(false);
        showConnectionToast(message ?? `${providerLabel} connected successfully.`, false);
        return;
      }

      if (status === 'error') {
        const errorMessage = message ?? `${providerLabel} authorization failed.`;
        setProviderErrorMessage(errorMessage);
        showConnectionToast(errorMessage, true);
      }
    }

    const subscription = Linking.addEventListener('url', (event) => {
      void handleProviderRedirect(event.url);
    });

    void Linking.getInitialURL().then((initialUrl) => {
      void handleProviderRedirect(initialUrl);
    });

    return () => {
      subscription.remove();
    };
  }, [authSession, backendUrl]);

  async function loadProviderStatus(showSpinner = true) {
    if (!authSession) {
      setProviderStatus([]);
      return;
    }

    if (showSpinner) {
      setProviderAction('refresh');
    }

    setProviderErrorMessage(null);

    try {
      const response = await fetchServiceStatus(backendUrl, authSession);
      setProviderStatus(response.services.filter((service) => service.name !== 'server'));
    } catch (error) {
      setProviderErrorMessage(
        error instanceof Error ? error.message : 'Failed to load provider status.',
      );
    } finally {
      if (showSpinner) {
        setProviderAction((currentAction) =>
          currentAction === 'refresh' ? null : currentAction,
        );
      }
    }
  }

  async function handleConnectQobuz() {
    if (!authSession) {
      showConnectionToast('Please log in before connecting a provider.', true);
      return;
    }

    const trimmedUsername = qobuzUsername.trim();
    const trimmedPassword = qobuzPassword.trim();

    if (!trimmedUsername || !trimmedPassword) {
      showConnectionToast('Please enter both your Qobuz username and password.', true);
      return;
    }

    const actionName = 'connect-qobuz';
    setProviderAction(actionName);
    setProviderErrorMessage(null);

    try {
      const message = await connectQobuzProvider(
        backendUrl,
        authSession,
        trimmedUsername,
        trimmedPassword,
      );
      setQobuzPassword('');
      await loadProviderStatus(false);
      showConnectionToast(message, false);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to connect to Qobuz.';
      setProviderErrorMessage(message);
      showConnectionToast(message, true);
    } finally {
      setProviderAction((currentAction) =>
        currentAction === actionName ? null : currentAction,
      );
    }
  }

  async function handleConnectSpotify() {
    if (!authSession) {
      showConnectionToast('Please log in before connecting a provider.', true);
      return;
    }

    const actionName = 'connect-spotify';
    setProviderAction(actionName);
    setProviderErrorMessage(null);

    try {
      const response = await fetchSpotifyAuthUrl(
        backendUrl,
        authSession,
        SPOTIFY_APP_REDIRECT_URL,
      );
      await Linking.openURL(response.auth_url);
      showConnectionToast(
        'Complete Spotify authorization in your browser. The app will reopen automatically.',
        false,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to start Spotify authorization.';
      setProviderErrorMessage(message);
      showConnectionToast(message, true);
    } finally {
      setProviderAction((currentAction) =>
        currentAction === actionName ? null : currentAction,
      );
    }
  }

  async function handleConnectTidal() {
    if (!authSession) {
      showConnectionToast('Please log in before connecting a provider.', true);
      return;
    }

    const actionName = 'connect-tidal';
    setProviderAction(actionName);
    setProviderErrorMessage(null);

    try {
      const response = await fetchTidalAuthUrl(backendUrl, authSession, TIDAL_APP_REDIRECT_URL);
      await Linking.openURL(response.auth_url);
      showConnectionToast(
        'Complete Tidal authorization in your browser. The app will reopen automatically.',
        false,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to start Tidal authorization.';
      setProviderErrorMessage(message);
      showConnectionToast(message, true);
    } finally {
      setProviderAction((currentAction) =>
        currentAction === actionName ? null : currentAction,
      );
    }
  }

  async function handleDisconnectProvider(serviceName: 'qobuz' | 'spotify' | 'tidal') {
    if (!authSession) {
      showConnectionToast('Please log in before disconnecting a provider.', true);
      return;
    }

    const actionName = `disconnect-${serviceName}`;
    setProviderAction(actionName);
    setProviderErrorMessage(null);

    try {
      const message = await disconnectStreamingProvider(backendUrl, authSession, serviceName);
      await loadProviderStatus(false);
      showConnectionToast(message, false);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to disconnect provider.';
      setProviderErrorMessage(message);
      showConnectionToast(message, true);
    } finally {
      setProviderAction((currentAction) =>
        currentAction === actionName ? null : currentAction,
      );
    }
  }

  const qobuzProvider = providerStatus.find((service) => service.name === 'qobuz') ?? null;
  const spotifyProvider = providerStatus.find((service) => service.name === 'spotify') ?? null;
  const tidalProvider = providerStatus.find((service) => service.name === 'tidal') ?? null;

  return (
    <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
        Providers
      </Text>
      <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
        Connect external services the same way the Flutter app does, then refresh status after
        completing browser-based authorization.
      </Text>

      {authSession ? (
        <>
          <ProviderActionButton
            busy={providerAction === 'refresh'}
            label="Refresh provider status"
            onPress={() => {
              void loadProviderStatus();
            }}
            tone="secondary"
          />

          <QobuzProviderCard
            busyConnecting={providerAction === 'connect-qobuz'}
            busyDisconnecting={providerAction === 'disconnect-qobuz'}
            onConnect={() => {
              void handleConnectQobuz();
            }}
            onDisconnect={() => {
              void handleDisconnectProvider('qobuz');
            }}
            onPasswordChange={setQobuzPassword}
            onUsernameChange={setQobuzUsername}
            password={qobuzPassword}
            provider={qobuzProvider}
            username={qobuzUsername}
          />

          <SpotifyProviderCard
            busyConnecting={providerAction === 'connect-spotify'}
            busyDisconnecting={providerAction === 'disconnect-spotify'}
            onConnect={() => {
              void handleConnectSpotify();
            }}
            onDisconnect={() => {
              void handleDisconnectProvider('spotify');
            }}
            provider={spotifyProvider}
          />

          <TidalProviderCard
            busyConnecting={providerAction === 'connect-tidal'}
            busyDisconnecting={providerAction === 'disconnect-tidal'}
            onConnect={() => {
              void handleConnectTidal();
            }}
            onDisconnect={() => {
              void handleDisconnectProvider('tidal');
            }}
            provider={tidalProvider}
          />

          {providerErrorMessage ? (
            <View className="mt-4 rounded-[20px] border border-rose-200 bg-rose-50 px-4 py-4">
              <Text className="text-sm font-semibold text-rose-900">Provider connection failed</Text>
              <Text className="mt-1 text-sm text-rose-700">{providerErrorMessage}</Text>
            </View>
          ) : null}
        </>
      ) : (
        <Text className="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-400">
          Log in first to connect or disconnect music providers.
        </Text>
      )}
    </View>
  );
}

function getServerPreloadPhaseLabel(progress: ServerPreloadProgress | null) {
  if (!progress) {
    return 'Idle';
  }

  switch (progress.phase) {
    case 'scanning_files':
      return 'Scanning files';
    case 'importing_tracks':
      return 'Importing tracks';
    case 'syncing_albums':
      return 'Syncing albums';
    case 'syncing_playlists':
      return 'Syncing playlists';
    case 'completed':
      return 'Completed';
    case 'failed':
      return 'Failed';
    default:
      return progress.state === 'running' ? 'Running' : 'Idle';
  }
}

function getServerPreloadProgressRatio(progress: ServerPreloadProgress | null) {
  if (!progress) {
    return 0;
  }

  if (progress.state === 'completed') {
    return 1;
  }

  if (progress.total_files <= 0) {
    return 0;
  }

  return Math.min(1, Math.max(0, progress.processed_files / progress.total_files));
}

type ServerPreloadCardProps = {
  authSession: AuthSession | null;
  backendUrl: string;
};

function ServerPreloadCard({ authSession, backendUrl }: Readonly<ServerPreloadCardProps>) {
  const [progress, setProgress] = useState<ServerPreloadProgress | null>(null);
  const [preloadAction, setPreloadAction] = useState<ServerPreloadMode | null>(null);
  const [preloadErrorMessage, setPreloadErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!authSession) {
      setProgress(null);
      setPreloadErrorMessage(null);
      return;
    }

    void loadServerPreloadStatus();
  }, [authSession, backendUrl]);

  useEffect(() => {
    if (!authSession || progress?.state !== 'running') {
      return undefined;
    }

    const interval = setInterval(() => {
      void loadServerPreloadStatus(false);
    }, 1000);

    return () => {
      clearInterval(interval);
    };
  }, [authSession, backendUrl, progress?.state]);

  async function loadServerPreloadStatus(showErrors = true) {
    if (!authSession) {
      return;
    }

    try {
      const nextProgress = await fetchServerPreloadStatus(backendUrl, authSession);
      setProgress(nextProgress);
      if (showErrors) {
        setPreloadErrorMessage(null);
      }
    } catch (error) {
      if (!showErrors) {
        return;
      }

      setPreloadErrorMessage(
        error instanceof Error ? error.message : 'Failed to load server preload status.',
      );
    }
  }

  async function handleStartPreload(mode: ServerPreloadMode) {
    if (!authSession) {
      showConnectionToast('Please log in before preloading server media.', true);
      return;
    }

    setPreloadAction(mode);
    setPreloadErrorMessage(null);

    try {
      const nextProgress = await startServerPreload(backendUrl, authSession, mode);
      setProgress(nextProgress);
      showConnectionToast(
        mode === 'new_only'
          ? 'Server preload started in new-only mode.'
          : 'Server preload started in full recheck mode.',
        false,
      );
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Failed to start server preload.';
      setPreloadErrorMessage(message);
      showConnectionToast(message, true);

      if (message.toLowerCase().includes('already running')) {
        void loadServerPreloadStatus(false);
      }
    } finally {
      setPreloadAction((currentMode) => (currentMode === mode ? null : currentMode));
    }
  }

  const isRunning = progress?.state === 'running';
  const progressRatio = getServerPreloadProgressRatio(progress);
  const progressWidth: `${number}%` =
    progressRatio <= 0 ? '0%' : `${Math.max(6, progressRatio * 100)}%`;

  return (
    <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
      <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
        Server Library Preload
      </Text>
      <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
        Populate the server provider tables and canonical tables from your local server music. New-only mode imports unseen files by location. Full recheck re-reads every file and updates changed metadata. Both modes remove entries for files that no longer exist.
      </Text>

      {authSession ? (
        <>
          {progress ? (
            <View className="mt-4 rounded-[20px] border border-slate-200 bg-slate-50 px-4 py-4 dark:border-slate-700 dark:bg-slate-950">
              <View className="flex-row items-center justify-between gap-4">
                <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">
                  {getServerPreloadPhaseLabel(progress)}
                </Text>
                <Text className="text-sm font-semibold text-slate-500 dark:text-slate-400">
                  {progress.processed_files} / {progress.total_files}
                </Text>
              </View>

              <View className="mt-3 h-3 overflow-hidden rounded-full bg-slate-200 dark:bg-slate-800">
                <View
                  className="h-full rounded-full bg-teal-600"
                  style={{ width: progressWidth }}
                />
              </View>

              <Text className="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-400">
                Tracks: {progress.imported_tracks} new, {progress.updated_tracks} updated, {progress.skipped_tracks} unchanged, {progress.deleted_tracks} removed.
              </Text>
              <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
                Albums: {progress.imported_albums} new, {progress.updated_albums} updated, {progress.deleted_albums} removed.
              </Text>
              <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
                Playlists: {progress.imported_playlists} new, {progress.updated_playlists} updated, {progress.deleted_playlists} removed.
              </Text>
              <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
                Canonical links: {progress.canonical_tracks} tracks, {progress.canonical_albums} albums, {progress.canonical_playlists} playlists.
              </Text>

              {progress.current_item ? (
                <Text className="mt-3 text-sm leading-6 text-slate-500 dark:text-slate-400">
                  Current file: {progress.current_item}
                </Text>
              ) : null}

              {progress.error_message ? (
                <Text className="mt-3 text-sm font-semibold text-rose-700">
                  {progress.error_message}
                </Text>
              ) : null}
            </View>
          ) : null}

          <ProviderActionButton
            busy={preloadAction === 'new_only'}
            label="Import new files only"
            onPress={() => {
              void handleStartPreload('new_only');
            }}
            tone="primary"
          />

          <ProviderActionButton
            busy={preloadAction === 'recheck_all'}
            label="Recheck all files"
            onPress={() => {
              void handleStartPreload('recheck_all');
            }}
            tone="secondary"
          />

          <ProviderActionButton
            busy={false}
            label={isRunning ? 'Refresh running status' : 'Refresh preload status'}
            onPress={() => {
              void loadServerPreloadStatus();
            }}
            tone="secondary"
          />

          {preloadErrorMessage ? (
            <View className="mt-4 rounded-[20px] border border-rose-200 bg-rose-50 px-4 py-4">
              <Text className="text-sm font-semibold text-rose-900">Server preload failed</Text>
              <Text className="mt-1 text-sm text-rose-700">{preloadErrorMessage}</Text>
            </View>
          ) : null}
        </>
      ) : (
        <Text className="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-400">
          Log in first to start or monitor server preloading.
        </Text>
      )}
    </View>
  );
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
    themePreference,
    setThemePreference,
  } = useSettings();
  const [isPickingFolder, setIsPickingFolder] = useState(false);
  const [folderErrorMessage, setFolderErrorMessage] = useState<string | null>(null);
  const [backendUrlInput, setBackendUrlInput] = useState(backendUrl);
  const [connectionMessage, setConnectionMessage] = useState<string | null>(null);
  const [connectionTone, setConnectionTone] = useState<'success' | 'error' | null>(null);
  const [isTestingConnection, setIsTestingConnection] = useState(false);
  const isDarkMode = themePreference === 'dark';
  const folderButtonLabel = getFolderButtonLabel(isPickingFolder, selectedFolder);

  useEffect(() => {
    setBackendUrlInput(backendUrl);
  }, [backendUrl]);

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
    <SafeAreaView className="flex-1 bg-slate-50 dark:bg-slate-950" edges={["left", "right"]}>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 24, paddingTop: 16 }}
        keyboardShouldPersistTaps="handled"
      >
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500 dark:text-slate-400">
            Settings
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900 dark:text-slate-100">
            App Settings
          </Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-400">
            Configure the backend connection, manage your account, and choose the local folder
            that should be scanned recursively for playable audio files.
          </Text>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Appearance
          </Text>
          <View className="mt-4 flex-row items-center justify-between gap-4 rounded-[20px] border border-slate-200 bg-slate-50 px-4 py-4 dark:border-slate-700 dark:bg-slate-950">
            <View className="flex-1">
              <Text className="text-base font-semibold text-slate-900 dark:text-slate-100">Dark mode</Text>
              <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">
                Switch the main app surfaces, navigation, and player chrome to a darker palette.
              </Text>
            </View>
            <Switch
              ios_backgroundColor={isDarkMode ? '#334155' : '#cbd5e1'}
              onValueChange={(value) => {
                setThemePreference(value ? 'dark' : 'light');
              }}
              thumbColor={isDarkMode ? '#ffffff' : '#f8fafc'}
              trackColor={{ false: '#cbd5e1', true: '#0f766e' }}
              value={isDarkMode}
            />
          </View>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Backend
          </Text>
          <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
            Choose a quick preset or enter a custom backend URL.
          </Text>

          <TextInput
            autoCapitalize="none"
            autoCorrect={false}
            className="mt-4 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-100"
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
              className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
              onPress={() => {
                saveBackendUrl(REMOTE_BACKEND_URL);
              }}
            >
              <Text className="text-center text-base font-semibold text-slate-700 dark:text-slate-200">
                Use hosted backend
              </Text>
            </Pressable>

            <Pressable
              accessibilityRole="button"
              className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
              onPress={() => {
                saveBackendUrl(backendUrlInput);
              }}
            >
              <Text className="text-center text-base font-semibold text-slate-700 dark:text-slate-200">
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

          <Text className="mt-4 text-xs font-semibold uppercase tracking-[1px] text-slate-400 dark:text-slate-500">
            Saved backend
          </Text>
          <Text className="mt-1 text-sm leading-6 text-slate-600 dark:text-slate-400">{backendUrl}</Text>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Account
          </Text>
          {authSession ? (
            <>
              <Text className="mt-2 text-lg font-semibold text-slate-900 dark:text-slate-100">
                {authSession.user.username}
              </Text>
              <Text className="mt-1 text-sm leading-6 text-slate-500 dark:text-slate-400">
                {authSession.user.email}
              </Text>
            </>
          ) : (
            <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
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
              className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
              onPress={() => {
                navigation.navigate('Register');
              }}
            >
              <Text className="text-center text-base font-semibold text-slate-700 dark:text-slate-200">
                Register
              </Text>
            </Pressable>

            {authSession ? (
              <Pressable
                accessibilityRole="button"
                className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
                onPress={() => {
                  setAuthSession(null);
                  setConnectionTone('success');
                  setConnectionMessage('Stored session cleared.');
                }}
              >
                <Text className="text-center text-base font-semibold text-slate-700 dark:text-slate-200">
                  Clear saved session
                </Text>
              </Pressable>
            ) : null}
          </View>
        </View>

        <ProviderSettingsCard authSession={authSession} backendUrl={backendUrl} />

        <ServerPreloadCard authSession={authSession} backendUrl={backendUrl} />

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200 dark:bg-slate-900 dark:shadow-none">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-teal-700">
            Folder Access
          </Text>
          {selectedFolder ? (
            <>
              <Text className="mt-2 text-lg font-semibold text-slate-900 dark:text-slate-100">
                {selectedFolder.name}
              </Text>
              <Text className="mt-1 text-sm leading-6 text-slate-500 dark:text-slate-400">
                {selectedFolder.pathLabel}
              </Text>
            </>
          ) : (
            <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
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
                className="rounded-full border border-slate-200 bg-white px-5 py-4 active:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:active:bg-slate-800"
                onPress={() => {
                  setSelectedFolder(null);
                  setFolderErrorMessage(null);
                }}
              >
                <Text className="text-center text-base font-semibold text-slate-700 dark:text-slate-200">
                  Clear selection
                </Text>
              </Pressable>
            ) : null}
          </View>
        </View>

        <View className="mt-4 rounded-[24px] border border-slate-200 bg-white px-4 py-4 dark:border-slate-800 dark:bg-slate-900">
          <Text className="text-xs font-semibold uppercase tracking-[1.5px] text-slate-500 dark:text-slate-400">
            Supported Formats
          </Text>
          <Text className="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-400">
            Files are treated as playable when their extension matches:
          </Text>
          <View className="mt-3 flex-row flex-wrap gap-2">
            {PLAYABLE_AUDIO_EXTENSIONS.map((extension) => (
              <View key={extension} className="rounded-full bg-slate-100 px-3 py-2 dark:bg-slate-800">
                <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-700 dark:text-slate-200">
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