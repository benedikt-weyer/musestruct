import { Image, Text, View } from 'react-native';

type PlaylistArtworkProps = Readonly<{
  coverUrl?: string | null;
  fallbackLabel: string;
  previewCoverUrls?: Array<string | null | undefined>;
  size?: number;
}>;

function normalizePreviewCoverUrls(previewCoverUrls?: Array<string | null | undefined>) {
  if (!previewCoverUrls) {
    return [] as string[];
  }

  const normalizedUrls: string[] = [];
  for (const previewCoverUrl of previewCoverUrls) {
    const normalizedUrl = previewCoverUrl?.trim();
    if (!normalizedUrl || normalizedUrls.includes(normalizedUrl)) {
      continue;
    }

    normalizedUrls.push(normalizedUrl);
    if (normalizedUrls.length === 4) {
      break;
    }
  }

  return normalizedUrls;
}

export function PlaylistArtwork({
  coverUrl,
  fallbackLabel,
  previewCoverUrls,
  size = 80,
}: PlaylistArtworkProps) {
  const normalizedPreviewCoverUrls = normalizePreviewCoverUrls(previewCoverUrls);
  const artworkStyle = {
    width: size,
    height: size,
    borderRadius: 18,
  } as const;

  if (coverUrl) {
    return (
      <Image
        className="bg-slate-100 dark:bg-slate-800"
        resizeMode="cover"
        source={{ uri: coverUrl }}
        style={artworkStyle}
      />
    );
  }

  if (normalizedPreviewCoverUrls.length === 1) {
    return (
      <Image
        className="bg-slate-100 dark:bg-slate-800"
        resizeMode="cover"
        source={{ uri: normalizedPreviewCoverUrls[0] }}
        style={artworkStyle}
      />
    );
  }

  if (normalizedPreviewCoverUrls.length > 1) {
    return (
      <View className="flex-row flex-wrap overflow-hidden bg-slate-100 dark:bg-slate-800" style={artworkStyle}>
        {Array.from({ length: 4 }, (_, index) => {
          const previewCoverUrl = normalizedPreviewCoverUrls[index];
          return previewCoverUrl ? (
            <Image
              key={`${previewCoverUrl}-${index}`}
              resizeMode="cover"
              source={{ uri: previewCoverUrl }}
              style={{ width: '50%', height: '50%' }}
            />
          ) : (
            <View
              className="bg-slate-200 dark:bg-slate-700"
              key={`blank-${index}`}
              style={{ width: '50%', height: '50%' }}
            />
          );
        })}
      </View>
    );
  }

  return (
    <View className="items-center justify-center bg-slate-100 dark:bg-slate-800" style={artworkStyle}>
      <Text className="px-2 text-center text-xs font-semibold uppercase tracking-[1px] text-slate-500 dark:text-slate-400">
        {fallbackLabel}
      </Text>
    </View>
  );
}