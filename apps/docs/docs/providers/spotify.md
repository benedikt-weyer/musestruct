# Spotify Setup

## What Spotify is used for here

In this workspace, Spotify is used through the backend OAuth flow and the Web API.

Current behavior:

- browser-based OAuth connect flow from the app settings screen
- backend token storage and refresh
- search and metadata access
- library access
- preview playback when Spotify exposes a preview URL for a track

## Backend env

Add the following values to `apps/backend/.env`:

```env
SPOTIFY_CLIENT_ID=your_spotify_client_id
SPOTIFY_CLIENT_SECRET=your_spotify_client_secret
# optional
SPOTIFY_REDIRECT_URI=http://127.0.0.1:8080/api/streaming/spotify/callback
```

If `SPOTIFY_REDIRECT_URI` is omitted, the backend derives the callback URL from the request host.

## Spotify developer dashboard setup

1. Open the Spotify developer dashboard.
2. Create or reuse an application for Musestruct.
3. Copy the client ID and client secret into `apps/backend/.env`.
4. Add the backend callback URL to the app settings.

Recommended development callback URLs:

- `http://127.0.0.1:8080/api/streaming/spotify/callback`
- `http://localhost:8080/api/streaming/spotify/callback`

If you are using the React Native deep-link return flow, the backend callback still needs to be the HTTP callback above. The backend completes the token exchange and then redirects the browser back into the app with `musestruct://spotify`.

## Connect flow in the app

1. Start the backend.
2. Open the React Native app.
3. Go to Settings.
4. Make sure the backend URL points at your running backend.
5. Tap **Connect Spotify**.
6. Complete the Spotify browser authorization flow.
7. The app should reopen through the `musestruct://spotify` deep link.

## Troubleshooting

### Redirect mismatch

If Spotify reports a redirect mismatch, verify that:

- the callback URL in the Spotify dashboard exactly matches the backend callback URL
- the backend is receiving requests on the same host and port you registered
- your reverse proxy is forwarding the expected host and scheme if you derive redirects dynamically

### Connected but playback fails

Spotify playback in this codebase is limited to tracks that include a preview URL. If a track does not expose a preview, playback is expected to be unavailable.
