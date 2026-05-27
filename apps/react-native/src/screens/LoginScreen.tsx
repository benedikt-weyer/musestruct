import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useSettings } from '../context/SettingsContext';
import { loginWithBackend } from '../services/backendApi';

export function LoginScreen() {
  const { backendUrl, setAuthSession } = useSettings();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [messageTone, setMessageTone] = useState<'success' | 'error' | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleLogin() {
    setIsSubmitting(true);
    setMessage(null);
    setMessageTone(null);

    try {
      const session = await loginWithBackend(backendUrl, {
        email: email.trim(),
        password,
      });

      setAuthSession(session);
      setPassword('');
      setMessage('Login successful. You can return to Settings now.');
      setMessageTone('success');
    } catch (error) {
      setMessage(
        error instanceof Error ? error.message : 'The login request failed unexpectedly.',
      );
      setMessageTone('error');
    } finally {
      setIsSubmitting(false);
    }
  }

  const messageClasses =
    messageTone === 'error'
      ? 'mt-4 rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4'
      : 'mt-4 rounded-[24px] border border-teal-200 bg-teal-50 px-4 py-4';
  const messageTextClasses =
    messageTone === 'error' ? 'text-sm text-rose-700' : 'text-sm text-teal-700';

  return (
    <SafeAreaView className="flex-1 bg-slate-50" edges={['left', 'right']}>
      <View className="flex-1 px-5 pb-6 pt-4">
        <View className="rounded-[28px] bg-white px-5 py-5 shadow-sm shadow-slate-200">
          <Text className="text-xs font-semibold uppercase tracking-[2px] text-slate-500">
            Account
          </Text>
          <Text className="mt-2 text-3xl font-bold text-slate-900">Login</Text>
          <Text className="mt-3 text-sm leading-6 text-slate-600">
            Sign in against the configured Musestruct backend.
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

          <Text className="mt-4 text-sm font-semibold text-slate-700">Password</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="current-password"
            autoCorrect={false}
            className="mt-2 rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-3 text-base text-slate-900"
            importantForAutofill="yes"
            onChangeText={setPassword}
            placeholder="Password"
            placeholderTextColor="#94a3b8"
            returnKeyType="done"
            textContentType="password"
            secureTextEntry
            value={password}
          />

          <Pressable
            accessibilityRole="button"
            className="mt-5 rounded-full bg-slate-900 px-5 py-4 active:bg-slate-700"
            disabled={isSubmitting}
            onPress={() => {
              void handleLogin();
            }}
          >
            {isSubmitting ? (
              <ActivityIndicator color="#ffffff" />
            ) : (
              <Text className="text-center text-base font-semibold text-white">Login</Text>
            )}
          </Pressable>
        </View>

        {message ? (
          <View className={messageClasses}>
            <Text className={messageTextClasses}>{message}</Text>
          </View>
        ) : null}
      </View>
    </SafeAreaView>
  );
}