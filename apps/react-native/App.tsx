import './global.css';

import { useEffect } from 'react';
import { StatusBar } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { colorScheme } from 'nativewind';

import { ExpandedPlayerSheet } from './src/components/player/ExpandedPlayerSheet';
import { PlayerProvider } from './src/context/PlayerContext';
import { SettingsProvider, useSettings } from './src/context/SettingsContext';
import { AppNavigator } from './src/navigation/AppNavigator';

function AppShell() {
  const { themePreference } = useSettings();
  const isDarkMode = themePreference === 'dark';

  useEffect(() => {
    colorScheme.set(themePreference);
  }, [themePreference]);

  return (
    <>
      <StatusBar
        barStyle={isDarkMode ? 'light-content' : 'dark-content'}
        backgroundColor={isDarkMode ? '#020617' : '#f8fafc'}
      />
      <AppNavigator />
      <ExpandedPlayerSheet />
    </>
  );
}

function App() {
  return (
    <GestureHandlerRootView className="flex-1 bg-slate-50 dark:bg-slate-950">
      <SafeAreaProvider>
        <PlayerProvider>
          <SettingsProvider>
            <AppShell />
          </SettingsProvider>
        </PlayerProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

export default App;
