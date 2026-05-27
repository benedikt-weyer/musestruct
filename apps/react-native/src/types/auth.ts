export type BackendUser = {
  id: string;
  email: string;
  username: string;
  created_at: string;
  is_active: boolean;
};

export type AuthSession = {
  user: BackendUser;
  sessionToken: string;
};