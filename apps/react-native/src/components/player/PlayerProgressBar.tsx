import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';

type PlayerProgressBarProps = {
  currentTime: number;
  duration: number;
  interactive?: boolean;
  onSeek?: (timeInSeconds: number) => void;
};

function formatTime(value: number) {
  const totalSeconds = Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

export function PlayerProgressBar({
  currentTime,
  duration,
  interactive = false,
  onSeek,
}: Readonly<PlayerProgressBarProps>) {
  const [trackWidth, setTrackWidth] = useState(0);
  const progress = duration > 0 ? Math.min(1, Math.max(0, currentTime / duration)) : 0;

  function handleSeek(locationX: number) {
    if (!interactive || !onSeek || trackWidth <= 0 || duration <= 0) {
      return;
    }

    const ratio = Math.min(1, Math.max(0, locationX / trackWidth));
    onSeek(duration * ratio);
  }

  return (
    <View>
      <Pressable
        accessibilityRole={interactive ? 'adjustable' : undefined}
        className="h-4 justify-center"
        onLayout={(event) => {
          setTrackWidth(event.nativeEvent.layout.width);
        }}
        onPress={
          interactive
            ? (event) => {
                handleSeek(event.nativeEvent.locationX);
              }
            : undefined
        }
      >
        <View className="h-1.5 rounded-full bg-slate-300">
          <View
            className="h-1.5 rounded-full bg-teal-600"
            style={{ width: `${progress * 100}%` }}
          />
        </View>
      </Pressable>

      <View className="mt-2 flex-row items-center justify-between">
        <Text className="text-xs font-medium text-slate-400">{formatTime(currentTime)}</Text>
        <Text className="text-xs font-medium text-slate-400">{formatTime(duration)}</Text>
      </View>
    </View>
  );
}