import Ionicons from '@react-native-vector-icons/ionicons';
import { ActivityIndicator, Image, Pressable, Text, View } from 'react-native';

import { usePlayer } from '../../context/PlayerContext';

export function MiniPlayerBar() {
  const {
    closeTrack,
    currentTrack,
    isBuffering,
    isPlaying,
    openExpanded,
    position,
    duration,
    togglePlayPause,
  } = usePlayer();

  if (!currentTrack) {
    return null;
  }

  return (
    <View className="border-t border-slate-200 bg-white px-4 pt-2 shadow-sm shadow-slate-200 dark:border-slate-800 dark:bg-slate-950 dark:shadow-none">
      <View className="h-1 overflow-hidden rounded-full bg-slate-200 dark:bg-slate-800">
        <View
          className="h-1 rounded-full bg-teal-600"
          style={{ width: `${duration > 0 ? Math.min(100, (position / duration) * 100) : 0}%` }}
        />
      </View>

      <View className="flex-row items-center py-3">
        <Pressable
          accessibilityRole="button"
          className="mr-3 flex-1 flex-row items-center"
          onPress={openExpanded}
        >
          {currentTrack.artworkUrl ? (
            <Image
              className="h-12 w-12 rounded-[14px] bg-slate-100 dark:bg-slate-800"
              resizeMode="cover"
              source={{ uri: currentTrack.artworkUrl }}
            />
          ) : (
            <View className="h-12 w-12 items-center justify-center rounded-[14px] bg-slate-100 dark:bg-slate-800">
              <Ionicons color="#475569" name="musical-notes-outline" size={22} />
            </View>
          )}

          <View className="ml-3 flex-1">
            <Text className="text-sm font-semibold text-slate-900 dark:text-slate-100" numberOfLines={1}>
              {currentTrack.title}
            </Text>
            <Text className="mt-1 text-xs text-slate-500 dark:text-slate-400" numberOfLines={1}>
              {currentTrack.artist}
            </Text>
          </View>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="mr-2 h-11 w-11 items-center justify-center rounded-full bg-slate-900 active:bg-slate-700"
          onPress={togglePlayPause}
        >
          {isBuffering ? (
            <ActivityIndicator color="#ffffff" size="small" />
          ) : (
            <Ionicons color="#ffffff" name={isPlaying ? 'pause' : 'play'} size={20} />
          )}
        </Pressable>

        <Pressable
          accessibilityRole="button"
          className="h-11 w-11 items-center justify-center rounded-full bg-slate-100 active:bg-slate-200 dark:bg-slate-800 dark:active:bg-slate-700"
          onPress={closeTrack}
        >
          <Ionicons color="#334155" name="close" size={18} />
        </Pressable>
      </View>
    </View>
  );
}