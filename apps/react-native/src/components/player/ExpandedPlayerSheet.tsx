import Ionicons from '@react-native-vector-icons/ionicons';
import { ActivityIndicator, Image, Modal, Pressable, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { usePlayer } from '../../context/PlayerContext';
import { PlayerProgressBar } from './PlayerProgressBar';

function formatSource(source: string) {
  if (!source) {
    return 'Unknown source';
  }

  return source
    .split(/[_-]/)
    .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
    .join(' ');
}

export function ExpandedPlayerSheet() {
  const {
    closeExpanded,
    closeTrack,
    currentTrack,
    duration,
    errorMessage,
    isBuffering,
    isExpanded,
    isPlaying,
    position,
    seekTo,
    togglePlayPause,
  } = usePlayer();

  if (!currentTrack) {
    return null;
  }

  return (
    <Modal animationType="slide" presentationStyle="fullScreen" visible={isExpanded}>
      <SafeAreaView className="flex-1 bg-slate-950">
        <View className="flex-1 px-6 pb-8 pt-4">
          <View className="flex-row items-center justify-between">
            <Pressable
              accessibilityRole="button"
              className="h-11 w-11 items-center justify-center rounded-full bg-slate-900 active:bg-slate-800"
              onPress={closeExpanded}
            >
              <Ionicons color="#e2e8f0" name="chevron-down" size={22} />
            </Pressable>
            <Text className="text-sm font-semibold uppercase tracking-[2px] text-slate-400">
              Now Playing
            </Text>
            <Pressable
              accessibilityRole="button"
              className="h-11 w-11 items-center justify-center rounded-full bg-slate-900 active:bg-slate-800"
              onPress={closeTrack}
            >
              <Ionicons color="#e2e8f0" name="close" size={18} />
            </Pressable>
          </View>

          <View className="mt-10 items-center">
            {currentTrack.artworkUrl ? (
              <Image
                className="h-80 w-80 rounded-[32px] bg-slate-900"
                resizeMode="cover"
                source={{ uri: currentTrack.artworkUrl }}
              />
            ) : (
              <View className="h-80 w-80 items-center justify-center rounded-[32px] bg-slate-900">
                <Ionicons color="#94a3b8" name="musical-notes-outline" size={72} />
              </View>
            )}
          </View>

          <View className="mt-10">
            <View className="flex-row items-start justify-between gap-4">
              <View className="flex-1">
                <Text className="text-3xl font-bold text-white" numberOfLines={2}>
                  {currentTrack.title}
                </Text>
                <Text className="mt-2 text-lg text-slate-300" numberOfLines={1}>
                  {currentTrack.artist}
                </Text>
                <Text className="mt-2 text-sm leading-6 text-slate-400" numberOfLines={2}>
                  {currentTrack.description ?? currentTrack.album ?? formatSource(currentTrack.source)}
                </Text>
              </View>
              <View className="rounded-full border border-slate-700 bg-slate-900 px-3 py-2">
                <Text className="text-xs font-semibold uppercase tracking-[1px] text-slate-300">
                  {formatSource(currentTrack.source)}
                </Text>
              </View>
            </View>

            <View className="mt-8">
              <PlayerProgressBar
                currentTime={position}
                duration={duration}
                interactive
                onSeek={seekTo}
              />
            </View>

            {errorMessage ? (
              <View className="mt-6 rounded-[20px] border border-rose-400/30 bg-rose-500/10 px-4 py-4">
                <Text className="text-sm font-semibold text-rose-200">Playback failed</Text>
                <Text className="mt-1 text-sm text-rose-100">{errorMessage}</Text>
              </View>
            ) : null}

            <View className="mt-10 flex-row items-center justify-center gap-5">
              <Pressable
                accessibilityRole="button"
                className="h-14 w-14 items-center justify-center rounded-full bg-slate-900 active:bg-slate-800"
                onPress={closeTrack}
              >
                <Ionicons color="#e2e8f0" name="stop" size={24} />
              </Pressable>

              <Pressable
                accessibilityRole="button"
                className="h-20 w-20 items-center justify-center rounded-full bg-teal-500 active:bg-teal-400"
                onPress={togglePlayPause}
              >
                {isBuffering ? (
                  <ActivityIndicator color="#062c2c" size="large" />
                ) : (
                  <Ionicons color="#062c2c" name={isPlaying ? 'pause' : 'play'} size={34} />
                )}
              </Pressable>
            </View>
          </View>
        </View>
      </SafeAreaView>
    </Modal>
  );
}