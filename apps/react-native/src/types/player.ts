export type PlayerTrack = {
  id: string;
  key: string;
  title: string;
  artist: string;
  album?: string;
  artworkUrl?: string | null;
  description?: string;
  duration?: number;
  source: string;
  url: string;
};

export type QueueTrack = Omit<PlayerTrack, 'url'>;

export type PlayerPlayMode = 'normal' | 'shuffle';

export type PlayerLoopMode = 'once' | 'twice' | 'infinite';