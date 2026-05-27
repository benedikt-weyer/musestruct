import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';

import { useSettings } from '../context/SettingsContext';
import type { RootStackParamList } from '../navigation/types';
import { registerWithBackend } from '../services/backendApi';

export function RegisterScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { backendUrl } = useSettings();
  const [email, setEmail] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleRegister() {
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await registerWithBackend(backendUrl, {
        email: email.trim(),
        username: username.trim(),
        password,
      });

      Alert.alert('Registration successful', 'You can now log in with your new account.');
      navigation.replace('Login');
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : 'The registration request failed unexpectedly.',
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <SafeAreaView className="flex-1 bg-slate-50" edges={['left', 'right']}>
      <View className="flex-1 px-5 pb-6 pt-4">
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500">
            Account
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900">Register</Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600">
            Create a new account against the configured Musestruct backend.
          </Text>
          <Text className="mt-3 text-xs font-semibold uppercase tracking-[1px] text-teal-700">
            {backendUrl}
          </Text>
        </View>

        <View className="mt-4 rounded-[24px] bg-white px-4 py-4 shadow-sm shadow-slate-200">
          <Text className="text-sm font-semibold text-slate-700">Email</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="username"
            autoCorrect={false}
            className="mt-2 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900"
            importantForAutofill="yes"
            keyboardType="email-address"
            onChangeText={setEmail}
            placeholder="you@example.com"
            placeholderTextColor="#94a3b8"
            returnKeyType="next"
            textContentType="username"
            value={email}
          />

          <Text className="mt-4 text-sm font-semibold text-slate-700">Username</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="nickname"
            autoCorrect={false}
            className="mt-2 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900"
            importantForAutofill="yes"
            onChangeText={setUsername}
            placeholder="your-name"
            placeholderTextColor="#94a3b8"
            returnKeyType="next"
            textContentType="nickname"
            value={username}
          />

          <Text className="mt-4 text-sm font-semibold text-slate-700">Password</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="new-password"
            autoCorrect={false}
            className="mt-2 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900"
            importantForAutofill="yes"
            onChangeText={setPassword}
            placeholder="Password"
            placeholderTextColor="#94a3b8"
            passwordRules="minlength: 8;"
            returnKeyType="done"
            textContentType="newPassword"
            secureTextEntry
            value={password}
          />

          <Pressable
            accessibilityRole="button"
            className="mt-5 rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
            disabled={isSubmitting}
            onPress={() => {
              void handleRegister();
            }}
          >
            {isSubmitting ? (
              <ActivityIndicator color="#ffffff" />
            ) : (
              <Text className="text-center text-base font-semibold text-white">Register</Text>
            )}
          </Pressable>
        </View>

        {errorMessage ? (
          <View className="mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4">
            <Text className="text-sm text-rose-700">{errorMessage}</Text>
          </View>
        ) : null}
      </View>
    </SafeAreaView>
  );
}