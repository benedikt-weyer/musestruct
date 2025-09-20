# Spotify OAuth2 Setup Guide

This guide will help you set up Spotify OAuth2 authentication for the Musestruct app.

## Prerequisites

- A Spotify account
- Access to the [Spotify Developer Console](https://developer.spotify.com/dashboard)

## Step 1: Create a Spotify App

1. Go to the [Spotify Developer Console](https://developer.spotify.com/dashboard)
2. Log in with your Spotify account
3. Click "Create an App"
4. Fill in the app details:
   - **App name**: `Musestruct` (or any name you prefer)
   - **App description**: `Music streaming app with multi-service support`
   - **Website**: `http://localhost:8080` (or your domain)
   - **Redirect URI**: `http://127.0.0.1:8080/api/streaming/spotify/callback`
   - **API/SDKs**: Check "Web API"
5. Click "Save"

## Step 2: Get Your Credentials

After creating the app, you'll see your app dashboard. Note down:

- **Client ID**: This will be displayed on the app dashboard
- **Client Secret**: Click "Show client secret" to reveal it

## Step 3: Configure Environment Variables

Create a `.env` file in the backend directory (`/home/benedikt/Git/musestruct/backend/.env`) with the following content:

```env
# Spotify OAuth2 Configuration
SPOTIFY_CLIENT_ID=your_client_id_here
SPOTIFY_CLIENT_SECRET=your_client_secret_here
SPOTIFY_REDIRECT_URI=http://127.0.0.1:8080/api/streaming/spotify/callback

# Other existing environment variables...
DATABASE_URL=your_database_url
# ... other variables
```

Replace `your_client_id_here` and `your_client_secret_here` with the actual values from your Spotify app.

## Step 4: Update Redirect URIs (Important!)

In your Spotify app settings, make sure to add these redirect URIs:

### For Development:
- `http://127.0.0.1:8080/api/streaming/spotify/callback`
- `http://localhost:8080/api/streaming/spotify/callback` (alternative)

### For Production (when you deploy):
- `https://yourdomain.com/api/streaming/spotify/callback`

## Step 5: Test the Integration

1. Start your backend server:
   ```bash
   cd backend
   cargo run
   ```

2. Start your Flutter app:
   ```bash
   cd ..
   flutter run
   ```

3. In the app, go to Settings and try to connect to Spotify
4. The app should open your browser and redirect to Spotify's authorization page
5. After authorizing, you should be redirected back to your app

## Troubleshooting

### "INVALID_CLIENT: Invalid redirect URI" Error

This error occurs when the redirect URI in your Spotify app settings doesn't match the one being used. Make sure:

1. The redirect URI in your Spotify app settings exactly matches: `http://127.0.0.1:8080/api/streaming/spotify/callback`
2. You've saved the changes in the Spotify Developer Console
3. You're using the correct Client ID

### "INVALID_CLIENT: Invalid client" Error

This usually means:
1. The Client ID is incorrect
2. The Client Secret is incorrect
3. The app is not properly configured

### "access_denied" Error

This means the user denied permission during the OAuth flow. This is normal user behavior.

## OAuth2 Flow Explanation

The Spotify OAuth2 flow works as follows:

1. **Authorization Request**: User clicks "Connect Spotify" in the app
2. **Browser Redirect**: App opens browser with Spotify authorization URL
3. **User Authorization**: User logs in to Spotify and grants permissions
4. **Authorization Code**: Spotify redirects back to your app with an authorization code
5. **Token Exchange**: Your backend exchanges the code for access and refresh tokens
6. **Token Storage**: Tokens are stored in the database for the user
7. **API Access**: App can now make authenticated requests to Spotify API

## Required Spotify Scopes

The app requests these minimal permissions from Spotify:

- `user-read-playback-state`: Read user's current playback state
- `user-modify-playback-state`: Control user's playback
- `user-read-currently-playing`: Read currently playing track
- `streaming`: Access to streaming functionality
- `playlist-read-private`: Read user's private playlists
- `playlist-read-collaborative`: Read collaborative playlists
- `user-library-read`: Read user's saved tracks and albums

## Security Notes

- Never commit your `.env` file to version control
- Keep your Client Secret secure
- Use HTTPS in production
- Consider implementing PKCE (Proof Key for Code Exchange) for additional security

## Next Steps

Once OAuth2 is working, you can:

1. Implement the Spotify Web Playback SDK for actual music playback
2. Add playlist management features
3. Implement user's library browsing
4. Add search functionality across Spotify's catalog

For more information, refer to the [Spotify Web API documentation](https://developer.spotify.com/documentation/web-api/).
