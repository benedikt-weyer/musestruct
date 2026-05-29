use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

const UP_SQL: &str = r#"
CREATE TABLE IF NOT EXISTS spotify_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_track_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album_name TEXT,
    duration INTEGER,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_track_id)
);

CREATE TABLE IF NOT EXISTS spotify_albums (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_album_id TEXT NOT NULL,
    name TEXT NOT NULL,
    artist TEXT NOT NULL,
    track_signature TEXT,
    release_date TEXT,
    cover_url TEXT,
    track_count INTEGER,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_album_id)
);

CREATE TABLE IF NOT EXISTS spotify_playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_playlist_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    owner_name TEXT,
    content_signature TEXT,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_playlist_id)
);

CREATE TABLE IF NOT EXISTS spotify_album_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    album_id UUID NOT NULL REFERENCES spotify_albums(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES spotify_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (album_id, track_id),
    UNIQUE (album_id, position)
);

CREATE TABLE IF NOT EXISTS spotify_playlist_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES spotify_playlists(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES spotify_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    added_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (playlist_id, track_id),
    UNIQUE (playlist_id, position)
);

CREATE TABLE IF NOT EXISTS tidal_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_track_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album_name TEXT,
    duration INTEGER,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_track_id)
);

CREATE TABLE IF NOT EXISTS tidal_albums (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_album_id TEXT NOT NULL,
    name TEXT NOT NULL,
    artist TEXT NOT NULL,
    track_signature TEXT,
    release_date TEXT,
    cover_url TEXT,
    track_count INTEGER,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_album_id)
);

CREATE TABLE IF NOT EXISTS tidal_playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_playlist_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    owner_name TEXT,
    content_signature TEXT,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_playlist_id)
);

CREATE TABLE IF NOT EXISTS tidal_album_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    album_id UUID NOT NULL REFERENCES tidal_albums(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES tidal_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (album_id, track_id),
    UNIQUE (album_id, position)
);

CREATE TABLE IF NOT EXISTS tidal_playlist_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES tidal_playlists(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES tidal_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    added_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (playlist_id, track_id),
    UNIQUE (playlist_id, position)
);

CREATE TABLE IF NOT EXISTS qobuz_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_track_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album_name TEXT,
    duration INTEGER,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_track_id)
);

CREATE TABLE IF NOT EXISTS qobuz_albums (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_album_id TEXT NOT NULL,
    name TEXT NOT NULL,
    artist TEXT NOT NULL,
    track_signature TEXT,
    release_date TEXT,
    cover_url TEXT,
    track_count INTEGER,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_album_id)
);

CREATE TABLE IF NOT EXISTS qobuz_playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_playlist_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    owner_name TEXT,
    content_signature TEXT,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_playlist_id)
);

CREATE TABLE IF NOT EXISTS qobuz_album_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    album_id UUID NOT NULL REFERENCES qobuz_albums(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES qobuz_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (album_id, track_id),
    UNIQUE (album_id, position)
);

CREATE TABLE IF NOT EXISTS qobuz_playlist_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES qobuz_playlists(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES qobuz_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    added_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (playlist_id, track_id),
    UNIQUE (playlist_id, position)
);

CREATE TABLE IF NOT EXISTS server_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_track_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album_name TEXT,
    duration INTEGER,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_track_id)
);

CREATE TABLE IF NOT EXISTS server_albums (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_album_id TEXT NOT NULL,
    name TEXT NOT NULL,
    artist TEXT NOT NULL,
    track_signature TEXT,
    release_date TEXT,
    cover_url TEXT,
    track_count INTEGER,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_album_id)
);

CREATE TABLE IF NOT EXISTS server_playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_playlist_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    owner_name TEXT,
    content_signature TEXT,
    cover_url TEXT,
    provider_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_playlist_id)
);

CREATE TABLE IF NOT EXISTS server_album_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    album_id UUID NOT NULL REFERENCES server_albums(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES server_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (album_id, track_id),
    UNIQUE (album_id, position)
);

CREATE TABLE IF NOT EXISTS server_playlist_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES server_playlists(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES server_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    added_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (playlist_id, track_id),
    UNIQUE (playlist_id, position)
);

CREATE TABLE IF NOT EXISTS canonical_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album_name TEXT,
    duration INTEGER,
    cover_url TEXT,
    normalized_title TEXT NOT NULL,
    normalized_artist TEXT NOT NULL,
    spotify_track_id UUID REFERENCES spotify_tracks(id) ON DELETE SET NULL,
    tidal_track_id UUID REFERENCES tidal_tracks(id) ON DELETE SET NULL,
    qobuz_track_id UUID REFERENCES qobuz_tracks(id) ON DELETE SET NULL,
    server_track_id UUID REFERENCES server_tracks(id) ON DELETE SET NULL,
    match_status TEXT NOT NULL DEFAULT 'resolved',
    unresolved_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS canonical_albums (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    artist TEXT NOT NULL,
    track_signature TEXT,
    release_date TEXT,
    cover_url TEXT,
    normalized_name TEXT NOT NULL,
    normalized_artist TEXT NOT NULL,
    spotify_album_id UUID REFERENCES spotify_albums(id) ON DELETE SET NULL,
    tidal_album_id UUID REFERENCES tidal_albums(id) ON DELETE SET NULL,
    qobuz_album_id UUID REFERENCES qobuz_albums(id) ON DELETE SET NULL,
    server_album_id UUID REFERENCES server_albums(id) ON DELETE SET NULL,
    match_status TEXT NOT NULL DEFAULT 'resolved',
    unresolved_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS canonical_playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    owner_name TEXT,
    normalized_name TEXT NOT NULL,
    content_signature TEXT,
    spotify_playlist_id UUID REFERENCES spotify_playlists(id) ON DELETE SET NULL,
    tidal_playlist_id UUID REFERENCES tidal_playlists(id) ON DELETE SET NULL,
    qobuz_playlist_id UUID REFERENCES qobuz_playlists(id) ON DELETE SET NULL,
    server_playlist_id UUID REFERENCES server_playlists(id) ON DELETE SET NULL,
    match_status TEXT NOT NULL DEFAULT 'resolved',
    unresolved_reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS canonical_album_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    album_id UUID NOT NULL REFERENCES canonical_albums(id) ON DELETE CASCADE,
    canonical_track_id UUID NOT NULL REFERENCES canonical_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (album_id, canonical_track_id),
    UNIQUE (album_id, position)
);

CREATE TABLE IF NOT EXISTS canonical_playlist_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES canonical_playlists(id) ON DELETE CASCADE,
    canonical_track_id UUID NOT NULL REFERENCES canonical_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    added_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (playlist_id, canonical_track_id),
    UNIQUE (playlist_id, position)
);

CREATE TABLE IF NOT EXISTS user_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    canonical_track_id UUID NOT NULL REFERENCES canonical_tracks(id) ON DELETE CASCADE,
    source TEXT NOT NULL,
    provider_track_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album_name TEXT,
    duration INTEGER,
    cover_url TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, source, provider_track_id)
);

CREATE TABLE IF NOT EXISTS user_playlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    canonical_playlist_id UUID REFERENCES canonical_playlists(id) ON DELETE SET NULL,
    source TEXT,
    provider_playlist_id TEXT,
    name TEXT NOT NULL,
    description TEXT,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    is_read_only BOOLEAN NOT NULL DEFAULT FALSE,
    is_watched BOOLEAN NOT NULL DEFAULT FALSE,
    last_synced_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_playlist_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    playlist_id UUID NOT NULL REFERENCES user_playlists(id) ON DELETE CASCADE,
    item_type TEXT NOT NULL,
    user_track_id UUID REFERENCES user_tracks(id) ON DELETE CASCADE,
    nested_playlist_id UUID REFERENCES user_playlists(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CHECK (item_type IN ('track', 'playlist')),
    CHECK (
        (item_type = 'track' AND user_track_id IS NOT NULL AND nested_playlist_id IS NULL) OR
        (item_type = 'playlist' AND nested_playlist_id IS NOT NULL AND user_track_id IS NULL)
    ),
    UNIQUE (playlist_id, position)
);

CREATE TABLE IF NOT EXISTS queue_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_track_id UUID NOT NULL REFERENCES user_tracks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    added_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, position)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_tracks_spotify_track_id ON canonical_tracks(spotify_track_id) WHERE spotify_track_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_tracks_tidal_track_id ON canonical_tracks(tidal_track_id) WHERE tidal_track_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_tracks_qobuz_track_id ON canonical_tracks(qobuz_track_id) WHERE qobuz_track_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_tracks_server_track_id ON canonical_tracks(server_track_id) WHERE server_track_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_canonical_tracks_search ON canonical_tracks(normalized_title, normalized_artist);

CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_albums_spotify_album_id ON canonical_albums(spotify_album_id) WHERE spotify_album_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_albums_tidal_album_id ON canonical_albums(tidal_album_id) WHERE tidal_album_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_albums_qobuz_album_id ON canonical_albums(qobuz_album_id) WHERE qobuz_album_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_albums_server_album_id ON canonical_albums(server_album_id) WHERE server_album_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_canonical_albums_search ON canonical_albums(normalized_name, normalized_artist);

CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_playlists_spotify_playlist_id ON canonical_playlists(spotify_playlist_id) WHERE spotify_playlist_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_playlists_tidal_playlist_id ON canonical_playlists(tidal_playlist_id) WHERE tidal_playlist_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_playlists_qobuz_playlist_id ON canonical_playlists(qobuz_playlist_id) WHERE qobuz_playlist_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_canonical_playlists_server_playlist_id ON canonical_playlists(server_playlist_id) WHERE server_playlist_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_canonical_playlists_search ON canonical_playlists(normalized_name);

CREATE INDEX IF NOT EXISTS idx_user_tracks_user_id ON user_tracks(user_id);
CREATE INDEX IF NOT EXISTS idx_user_playlists_user_id ON user_playlists(user_id);
CREATE INDEX IF NOT EXISTS idx_user_playlist_items_playlist_id ON user_playlist_items(playlist_id);
CREATE INDEX IF NOT EXISTS idx_queue_items_user_id ON queue_items(user_id);
"#;

const DOWN_SQL: &str = r#"
DROP TABLE IF EXISTS queue_items;
DROP TABLE IF EXISTS user_playlist_items;
DROP TABLE IF EXISTS user_playlists;
DROP TABLE IF EXISTS user_tracks;
DROP TABLE IF EXISTS canonical_playlist_tracks;
DROP TABLE IF EXISTS canonical_album_tracks;
DROP TABLE IF EXISTS canonical_playlists;
DROP TABLE IF EXISTS canonical_albums;
DROP TABLE IF EXISTS canonical_tracks;
DROP TABLE IF EXISTS server_playlist_tracks;
DROP TABLE IF EXISTS server_album_tracks;
DROP TABLE IF EXISTS server_playlists;
DROP TABLE IF EXISTS server_albums;
DROP TABLE IF EXISTS server_tracks;
DROP TABLE IF EXISTS qobuz_playlist_tracks;
DROP TABLE IF EXISTS qobuz_album_tracks;
DROP TABLE IF EXISTS qobuz_playlists;
DROP TABLE IF EXISTS qobuz_albums;
DROP TABLE IF EXISTS qobuz_tracks;
DROP TABLE IF EXISTS tidal_playlist_tracks;
DROP TABLE IF EXISTS tidal_album_tracks;
DROP TABLE IF EXISTS tidal_playlists;
DROP TABLE IF EXISTS tidal_albums;
DROP TABLE IF EXISTS tidal_tracks;
DROP TABLE IF EXISTS spotify_playlist_tracks;
DROP TABLE IF EXISTS spotify_album_tracks;
DROP TABLE IF EXISTS spotify_playlists;
DROP TABLE IF EXISTS spotify_albums;
DROP TABLE IF EXISTS spotify_tracks;
"#;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared(UP_SQL)
            .await
            .map(|_| ())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .get_connection()
            .execute_unprepared(DOWN_SQL)
            .await
            .map(|_| ())
    }
}