import './global.css';

import { Pressable, StatusBar, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

function App() {
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" backgroundColor="#f8fafc" />
      <SafeAreaView className="flex-1 bg-slate-50">
        <View className="flex-1 items-center justify-center px-6">
          <Pressable
            accessibilityRole="button"
            className="rounded-full bg-sky-600 px-6 py-4 active:bg-sky-700"
          >
            <Text className="text-base font-semibold text-white">
              Tap me
            </Text>
          </Pressable>
        </View>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

export default App;
