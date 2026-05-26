export type MusicFolder = {
  id: string;
  name: string;
  pathLabel: string;
  platform: 'android' | 'ios';
};

export type MusicFile = {
  id: string;
  name: string;
  pathLabel: string;
  extension: string;
  size: number;
  modifiedAt: number;
  uri: string;
};