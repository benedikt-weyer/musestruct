import './global.css';

import { StatusBar } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { SettingsProvider } from './src/context/SettingsContext';
import { AppNavigator } from './src/navigation/AppNavigator';

function App() {
  return (
    <GestureHandlerRootView className="flex-1">
      <SafeAreaProvider>
        <SettingsProvider>
          <StatusBar barStyle="dark-content" backgroundColor="#f8fafc" />
          <AppNavigator />
        </SettingsProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

export default App;
