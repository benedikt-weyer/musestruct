# Setup Overview

## Workspace overview

The current repository is organized as a monorepo with three active apps under `apps/`:

- `apps/backend`: Rust backend built with Axum and SeaORM.
- `apps/react-native`: React Native client with native Android playback and provider connection flows.
- `apps/flutter`: older Flutter client and related experiments.
- `apps/docs`: this MkDocs documentation app.

## Runtime pieces

### Backend

The backend is the integration point for:

- authentication and user accounts
- provider connections for Qobuz, Spotify, and Tidal
- catalog search and library lookups
- backend-managed local music scanning from the `own_music` directory

The backend environment file lives at `apps/backend/.env`, and the example template lives at `apps/backend/.env.example`.

### React Native app

The React Native app is the current mobile-facing client in this workspace. It provides:

- provider connection flows in Settings
- backend URL configuration
- playback using the Android native playback service
- on-device music folder selection for local file access inside the app

## Backend setup

1. Create the backend env file from the example:
   ```bash
   cp apps/backend/.env.example apps/backend/.env
   ```
2. Fill in the database settings you want to use.
3. Fill in only the provider credentials you actually need.
4. Start PostgreSQL and the backend:
   ```bash
   scripts/start-backend.sh
   ```

The backend script starts Docker Compose for PostgreSQL and then runs the backend from `apps/backend` with `cargo-watch`.

## Useful backend env variables

### Required for local development

```env
DATABASE_URL=postgresql://musestruct:change-me@localhost:5432/musestruct
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=musestruct
POSTGRES_USER=musestruct
POSTGRES_PASSWORD=change-me
SERVER_HOST=0.0.0.0
SERVER_PORT=8080
RUST_LOG=debug
```

### Optional provider env variables

```env
QOBUZ_APP_ID=
QOBUZ_SECRET=
SPOTIFY_CLIENT_ID=
SPOTIFY_CLIENT_SECRET=
SPOTIFY_REDIRECT_URI=
TIDAL_CLIENT_ID=
TIDAL_CLIENT_SECRET=
TIDAL_CLIENT_UNIQUE_KEY=
TIDAL_REDIRECT_URI=
TIDAL_COUNTRY_CODE=US
```

## Notes about redirects

Spotify and Tidal callback URLs can be derived automatically from the incoming request host, but explicit redirect env variables are still useful when:

- you deploy behind a proxy
- you need fixed callback URLs in the provider dashboard
- you want development and production callback URLs to be unambiguous
