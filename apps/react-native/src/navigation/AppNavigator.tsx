import {
  DefaultTheme,
  NavigationContainer,
  type RouteProp,
  type Theme,
} from '@react-navigation/native';
import {
  createBottomTabNavigator,
  type BottomTabNavigationOptions,
} from '@react-navigation/bottom-tabs';
import Ionicons from '@react-native-vector-icons/ionicons';

import { HomeScreen } from '../screens/HomeScreen';
import { SettingsScreen } from '../screens/SettingsScreen';

type RootTabParamList = {
  Home: undefined;
  Settings: undefined;
};

const Tab = createBottomTabNavigator<RootTabParamList>();

function getTabIconName(routeName: keyof RootTabParamList, focused: boolean) {
  if (routeName === 'Home') {
    return focused ? 'home' : 'home-outline';
  }

  return focused ? 'settings' : 'settings-outline';
}

function createScreenOptions({
  route,
}: {
  route: RouteProp<RootTabParamList, keyof RootTabParamList>;
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
      <Tab.Navigator
        screenOptions={createScreenOptions}
      >
        <Tab.Screen name="Home" component={HomeScreen} options={{ title: 'Home' }} />
        <Tab.Screen
          name="Settings"
          component={SettingsScreen}
          options={{ title: 'Settings' }}
        />
      </Tab.Navigator>
    </NavigationContainer>
  );
}