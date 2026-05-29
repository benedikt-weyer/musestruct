export type RootTabParamList = {
  Home: undefined;
  Library: undefined;
  Browse: undefined;
  Settings: undefined;
};

export type RootStackParamList = {
  Tabs: undefined;
  Login: undefined;
  Register: undefined;
  PlaylistDetails: {
    playlistId: string;
    playlistName: string;
    playlistDescription?: string | null;
  };
};