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

import type { RootStackParamList, RootTabParamList } from './types';
import { BrowseScreen } from '../screens/BrowseScreen';
import { HomeScreen } from '../screens/HomeScreen';
import { LibraryScreen } from '../screens/LibraryScreen';
import { LoginScreen } from '../screens/LoginScreen';
import { RegisterScreen } from '../screens/RegisterScreen';
import { SettingsScreen } from '../screens/SettingsScreen';
import { MiniPlayerBar } from '../components/player/MiniPlayerBar';

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
  route,
}: {
  route: { name: keyof RootTabParamList };
}): BottomTabNavigationOptions {
  return {
    headerShadowVisible: false,
    headerStyle: {
      backgroundColor: '#f8fafc',
    },
    headerTitleStyle: {
      fontWeight: '700',
    },
    tabBarActiveTintColor: '#0f766e',
    tabBarInactiveTintColor: '#64748b',
    tabBarStyle: {
      backgroundColor: '#ffffff',
      borderTopColor: '#e2e8f0',
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

function PlayerAwareTabBar(props: BottomTabBarProps) {
  return (
    <>
      <MiniPlayerBar />
      <BottomTabBar {...props} />
    </>
  );
}

function RootTabs() {
  return (
    <Tab.Navigator screenOptions={createScreenOptions} tabBar={(props) => <PlayerAwareTabBar {...props} />}>
      <Tab.Screen name="Home" component={HomeScreen} options={{ title: 'Home' }} />
      <Tab.Screen name="Library" component={LibraryScreen} options={{ title: 'Library' }} />
      <Tab.Screen name="Browse" component={BrowseScreen} options={{ title: 'Browse' }} />
      <Tab.Screen name="Settings" component={SettingsScreen} options={{ title: 'Settings' }} />
    </Tab.Navigator>
  );
}

const navigationTheme: Theme = {
  ...DefaultTheme,
  colors: {
    ...DefaultTheme.colors,
    background: '#f8fafc',
    card: '#ffffff',
    primary: '#0f766e',
    border: '#e2e8f0',
    text: '#0f172a',
  },
};

export function AppNavigator() {
  return (
    <NavigationContainer theme={navigationTheme}>
      <Stack.Navigator>
        <Stack.Screen component={RootTabs} name="Tabs" options={{ headerShown: false }} />
        <Stack.Screen component={LoginScreen} name="Login" options={{ title: 'Login' }} />
        <Stack.Screen
          component={RegisterScreen}
          name="Register"
          options={{ title: 'Register' }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}