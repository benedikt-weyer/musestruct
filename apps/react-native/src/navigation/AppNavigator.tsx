import {
  DefaultTheme,
  NavigationContainer,
  type Theme,
} from '@react-navigation/native';
import {
  BottomTabBar,
  type BottomTabBarProps,
  createBottomTabNavigator,
  type BottomTabNavigationOptions,
} from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import Ionicons from '@react-native-vector-icons/ionicons';

import { ExpandedPlayerSheet } from '../components/player/ExpandedPlayerSheet';
import { MiniPlayerBar } from '../components/player/MiniPlayerBar';
import { useSettings } from '../context/SettingsContext';
import type { RootStackParamList, RootTabParamList } from './types';
import { BrowseScreen } from '../screens/BrowseScreen';
import { HomeScreen } from '../screens/HomeScreen';
import { LibraryScreen } from '../screens/LibraryScreen';
import { LoginScreen } from '../screens/LoginScreen';
import { RegisterScreen } from '../screens/RegisterScreen';
import { SettingsScreen } from '../screens/SettingsScreen';

const Tab = createBottomTabNavigator<RootTabParamList>();
const Stack = createNativeStackNavigator<RootStackParamList>();

function getTabIconName(routeName: keyof RootTabParamList, focused: boolean) {
  if (routeName === 'Home') {
    return focused ? 'home' : 'home-outline';
  }

  if (routeName === 'Browse') {
    return focused ? 'search' : 'search-outline';
  }

  if (routeName === 'Library') {
    return focused ? 'library' : 'library-outline';
  }

  return focused ? 'settings' : 'settings-outline';
}

function createScreenOptions({
  isDarkMode,
  route,
}: {
  isDarkMode: boolean;
  route: { name: keyof RootTabParamList };
}): BottomTabNavigationOptions {
  return {
    headerShadowVisible: false,
    headerStyle: {
      backgroundColor: isDarkMode ? '#0f172a' : '#f8fafc',
    },
    headerTitleStyle: {
      color: isDarkMode ? '#e2e8f0' : '#0f172a',
      fontWeight: '700',
    },
    tabBarActiveTintColor: '#0f766e',
    tabBarInactiveTintColor: isDarkMode ? '#94a3b8' : '#64748b',
    tabBarStyle: {
      backgroundColor: isDarkMode ? '#0f172a' : '#ffffff',
      borderTopColor: isDarkMode ? '#1e293b' : '#e2e8f0',
      height: 68,
      paddingBottom: 8,
      paddingTop: 8,
    },
    tabBarLabelStyle: {
      fontSize: 12,
      fontWeight: '700',
    },
    tabBarIcon: ({ color, size, focused }) => (
      <Ionicons name={getTabIconName(route.name, focused)} size={size} color={color} />
    ),
  };
}

function PlayerAwareTabBar(props: Readonly<BottomTabBarProps>) {
  return (
    <>
      <MiniPlayerBar />
      <BottomTabBar {...props} />
    </>
  );
}

function RootTabs({ isDarkMode }: Readonly<{ isDarkMode: boolean }>) {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => createScreenOptions({ isDarkMode, route })}
      tabBar={PlayerAwareTabBar}
    >
      <Tab.Screen name="Home" component={HomeScreen} options={{ title: 'Home' }} />
      <Tab.Screen name="Library" component={LibraryScreen} options={{ title: 'Library' }} />
      <Tab.Screen name="Browse" component={BrowseScreen} options={{ title: 'Browse' }} />
      <Tab.Screen name="Settings" component={SettingsScreen} options={{ title: 'Settings' }} />
    </Tab.Navigator>
  );
}

export function AppNavigator() {
  const { themePreference } = useSettings();
  const isDarkMode = themePreference === 'dark';
  const navigationTheme: Theme = {
    ...DefaultTheme,
    colors: {
      ...DefaultTheme.colors,
      background: isDarkMode ? '#020617' : '#f8fafc',
      card: isDarkMode ? '#0f172a' : '#ffffff',
      primary: '#0f766e',
      border: isDarkMode ? '#1e293b' : '#e2e8f0',
      text: isDarkMode ? '#e2e8f0' : '#0f172a',
    },
  };

  return (
    <NavigationContainer theme={navigationTheme}>
      <>
        <Stack.Navigator>
          <Stack.Screen name="Tabs" options={{ headerShown: false }}>
            {() => <RootTabs isDarkMode={isDarkMode} />}
          </Stack.Screen>
          <Stack.Screen component={LoginScreen} name="Login" options={{ title: 'Login' }} />
          <Stack.Screen
            component={RegisterScreen}
            name="Register"
            options={{ title: 'Register' }}
          />
        </Stack.Navigator>
        <ExpandedPlayerSheet />
      </>
    </NavigationContainer>
  );
}