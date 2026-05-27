# Tidal Setup

## What Tidal is used for here

Tidal is integrated through the backend OAuth flow and Tidal API endpoints.

Current behavior:

- browser-based OAuth connect flow from the app settings screen
- backend token storage and refresh
- search and library access
- playback through backend-resolved Tidal playback URLs where the current player stack can consume them

## Backend env

Add the following values to `apps/backend/.env`:

```env
TIDAL_CLIENT_ID=your_tidal_client_id
TIDAL_CLIENT_SECRET=your_tidal_client_secret
# optional, only if your Tidal app config requires it
TIDAL_CLIENT_UNIQUE_KEY=
# optional
TIDAL_REDIRECT_URI=http://127.0.0.1:8080/api/streaming/tidal/callback
# optional
TIDAL_SCOPES=
# optional
TIDAL_COUNTRY_CODE=US
```

## Tidal app configuration

1. Create or reuse a Tidal developer application.
2. Copy the client ID and client secret into `apps/backend/.env`.
3. If your Tidal app uses a client unique key, set `TIDAL_CLIENT_UNIQUE_KEY` as well.
4. Add the backend callback URL to the Tidal app configuration.

Recommended development callback URLs:

- `http://127.0.0.1:8080/api/streaming/tidal/callback`
- `http://localhost:8080/api/streaming/tidal/callback`

As with Spotify, the provider callback is the backend HTTP URL. After completing the Tidal flow, the backend redirects back into the app with `musestruct://tidal`.

## Connect flow in the app

1. Start the backend.
2. Open the React Native app.
3. Go to Settings.
4. Make sure the backend URL points at your running backend.
5. Tap **Connect Tidal**.
6. Complete the browser authorization flow.
7. The app should reopen through the `musestruct://tidal` deep link.

## Playback notes

Tidal playback support in this workspace currently depends on what the backend can resolve from the Tidal API for a given track.

The backend currently tries, in order:

1. a direct track file playback URL
2. an HTTPS HLS playback manifest URL

Some tracks may still be unavailable to the current player stack if Tidal only serves DRM-protected playback metadata for them.

## Troubleshooting

### Tidal login completes but the app does not reconnect

Check these points:

- the Android app is installed with the deep-link host `musestruct://tidal`
- the backend callback URL matches what you configured in Tidal
- the backend is reachable from the device at the backend URL you configured in Settings

### Playback fails for some tracks

That usually means the track is being served in a form that the current player implementation cannot consume yet. Metadata and connection can still work even when playback for a specific track does not.
