import './global.css';

import { StatusBar } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { PlayerProvider } from './src/context/PlayerContext';
import { SettingsProvider, useSettings } from './src/context/SettingsContext';
import { AppNavigator } from './src/navigation/AppNavigator';

function AppShell() {
  const { themePreference } = useSettings();
  const isDarkMode = themePreference === 'dark';

  return (
    <>
      <StatusBar
        barStyle={isDarkMode ? 'light-content' : 'dark-content'}
        backgroundColor={isDarkMode ? '#020617' : '#f8fafc'}
      />
      <AppNavigator />
    </>
  );
}

function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <SettingsProvider>
          <PlayerProvider>
            <AppShell />
          </PlayerProvider>
        </SettingsProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

export default App;
