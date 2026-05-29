use anyhow::{Result, anyhow};
use sea_orm::{
    ActiveModelBehavior, ActiveModelTrait, ColumnTrait, ConnectionTrait, DatabaseConnection,
    EntityTrait, IntoActiveModel, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect, Set,
};
use serde::Serialize;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::str::FromStr;
use uuid::Uuid;

use crate::handlers::streaming::{get_valid_spotify_tokens, get_valid_tidal_tokens};
use crate::models::{
    CanonicalAlbumActiveModel, CanonicalAlbumColumn, CanonicalAlbumEntity, CanonicalAlbumTrackActiveModel,
    CanonicalAlbumTrackEntity, CanonicalPlaylistActiveModel, CanonicalPlaylistColumn, CanonicalPlaylistEntity,
    CanonicalPlaylistTrackActiveModel, CanonicalPlaylistTrackEntity, CanonicalTrackActiveModel,
    CanonicalTrackColumn, CanonicalTrackEntity, QobuzAlbumActiveModel, QobuzAlbumColumn, QobuzAlbumEntity,
    QobuzAlbumTrackActiveModel, QobuzAlbumTrackEntity, QobuzPlaylistActiveModel, QobuzPlaylistColumn,
    QobuzPlaylistEntity, QobuzPlaylistTrackActiveModel, QobuzPlaylistTrackEntity, QobuzTrackActiveModel,
    QobuzTrackColumn, QobuzTrackEntity, ServerAlbumActiveModel, ServerAlbumColumn, ServerAlbumEntity,
    ServerAlbumTrackActiveModel, ServerAlbumTrackEntity, ServerPlaylistActiveModel, ServerPlaylistColumn,
    ServerPlaylistEntity, ServerPlaylistTrackActiveModel, ServerPlaylistTrackEntity, ServerTrackActiveModel,
    ServerTrackColumn, ServerTrackEntity, SpotifyAlbumActiveModel, SpotifyAlbumColumn, SpotifyAlbumEntity,
    SpotifyAlbumTrackActiveModel, SpotifyAlbumTrackEntity, SpotifyPlaylistActiveModel, SpotifyPlaylistColumn,
    SpotifyPlaylistEntity, SpotifyPlaylistTrackActiveModel, SpotifyPlaylistTrackEntity, SpotifyTrackActiveModel,
    SpotifyTrackColumn, SpotifyTrackEntity, StreamingServiceColumn, StreamingServiceEntity,
    TidalAlbumActiveModel, TidalAlbumColumn, TidalAlbumEntity, TidalAlbumTrackActiveModel,
    TidalAlbumTrackEntity, TidalPlaylistActiveModel, TidalPlaylistColumn, TidalPlaylistEntity,
    TidalPlaylistTrackActiveModel, TidalPlaylistTrackEntity, TidalTrackActiveModel, TidalTrackColumn,
    TidalTrackEntity, UserPlaylistActiveModel, UserPlaylistColumn, UserPlaylistEntity,
    UserPlaylistItemActiveModel, UserPlaylistItemColumn, UserPlaylistItemEntity, UserTrackActiveModel,
    UserTrackColumn, UserTrackEntity,
};
use crate::services::streaming::{
    LocalMusicService, QobuzService, SpotifyService, StreamingAlbum, StreamingPlaylist, StreamingService,
    StreamingTrack, TidalService,
};

const PAGE_SIZE: u32 = 100;

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum LibraryProvider {
    Spotify,
    Tidal,
    Qobuz,
    Server,
}

impl LibraryProvider {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Spotify => "spotify",
            Self::Tidal => "tidal",
            Self::Qobuz => "qobuz",
            Self::Server => "server",
        }
    }
}

impl FromStr for LibraryProvider {
    type Err = anyhow::Error;

    fn from_str(value: &str) -> Result<Self> {
        match value {
            "spotify" => Ok(Self::Spotify),
            "tidal" => Ok(Self::Tidal),
            "qobuz" => Ok(Self::Qobuz),
            "server" => Ok(Self::Server),
            _ => Err(anyhow!("Unsupported provider: {}", value)),
        }
    }
}

#[derive(Debug, Serialize)]
pub struct ProviderRefreshSummary {
    pub provider: String,
    pub tracks: usize,
    pub albums: usize,
    pub playlists: usize,
    pub canonical_tracks: usize,
    pub canonical_albums: usize,
    pub canonical_playlists: usize,
    pub unresolved_tracks: usize,
    pub unresolved_albums: usize,
    pub unresolved_playlists: usize,
}

#[derive(Debug, Serialize)]
pub struct UserTrackSummary {
    pub id: Uuid,
    pub canonical_track_id: Uuid,
    pub provider_track_id: String,
    pub source: String,
    pub title: String,
    pub artist: String,
    pub album_name: Option<String>,
    pub duration: Option<i32>,
    pub cover_url: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UserPlaylistSummary {
    pub id: Uuid,
    pub canonical_playlist_id: Option<Uuid>,
    pub source: Option<String>,
    pub provider_playlist_id: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub is_public: bool,
    pub is_read_only: bool,
    pub is_watched: bool,
    pub last_synced_at: Option<chrono::NaiveDateTime>,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
}

#[derive(Debug, Serialize)]
pub struct UnresolvedMatchesResponse {
    pub tracks: Vec<CanonicalMatchSummary>,
    pub albums: Vec<CanonicalMatchSummary>,
    pub playlists: Vec<CanonicalMatchSummary>,
}

#[derive(Debug, Serialize)]
pub struct CanonicalMatchSummary {
    pub id: Uuid,
    pub name: String,
    pub artist_or_owner: Option<String>,
    pub reason: Option<String>,
}

#[derive(Clone)]
struct ProviderTrackState {
    provider_row_id: Uuid,
    canonical_track_id: Uuid,
    track: StreamingTrack,
}

#[derive(Clone)]
struct ProviderAlbumState {
    canonical_album_id: Uuid,
}

#[derive(Clone)]
struct ProviderPlaylistState {
    canonical_playlist_id: Uuid,
}

#[derive(Clone)]
struct TrackInput {
    provider_track_id: String,
    title: String,
    artist: String,
    album_name: Option<String>,
    duration: Option<i32>,
    cover_url: Option<String>,
    provider_metadata: Value,
}

#[derive(Clone)]
struct ProviderTrackReference {
    source: LibraryProvider,
    provider_track_id: String,
}

pub struct LibrarySyncService;

impl LibrarySyncService {
    pub async fn refresh_provider_library(
        db: &DatabaseConnection,
        user_id: Uuid,
        provider: LibraryProvider,
    ) -> Result<ProviderRefreshSummary> {
        let service = create_authenticated_streaming_service(provider, user_id, db).await?;
        clear_provider_cache(db, user_id, provider).await?;

        let mut provider_track_states: HashMap<String, ProviderTrackState> = HashMap::new();
        let mut canonical_track_ids = HashSet::new();
        let mut canonical_album_ids = HashSet::new();
        let mut canonical_playlist_ids = HashSet::new();
        let mut unresolved_tracks = 0usize;
        let mut unresolved_albums = 0usize;
        let mut unresolved_playlists = 0usize;

        for track in dedupe_tracks(fetch_library_tracks(service.as_ref()).await?) {
            let state = ensure_provider_track_state(db, user_id, provider, &mut provider_track_states, &track).await?;
            let canonical_track = CanonicalTrackEntity::find_by_id(state.canonical_track_id)
                .one(db)
                .await?
                .ok_or_else(|| anyhow!("Canonical track missing after refresh"))?;
            if canonical_track.match_status == "unresolved" {
                unresolved_tracks += 1;
            }
            canonical_track_ids.insert(state.canonical_track_id);
        }

        for album in fetch_library_albums(service.as_ref()).await? {
            let album_tracks = service.get_album_tracks(&album.id).await.unwrap_or_default();
            let state = sync_provider_album(
                db,
                user_id,
                provider,
                &album,
                &album_tracks,
                &mut provider_track_states,
            )
            .await?;
            let canonical_album = CanonicalAlbumEntity::find_by_id(state.canonical_album_id)
                .one(db)
                .await?
                .ok_or_else(|| anyhow!("Canonical album missing after refresh"))?;
            if canonical_album.match_status == "unresolved" {
                unresolved_albums += 1;
            }
            canonical_album_ids.insert(state.canonical_album_id);
        }

        for playlist in fetch_library_playlists(service.as_ref()).await? {
            let playlist_tracks = fetch_playlist_tracks(service.as_ref(), &playlist.id).await?;
            let state = sync_provider_playlist(
                db,
                user_id,
                provider,
                &playlist,
                &playlist_tracks,
                &mut provider_track_states,
            )
            .await?;
            let canonical_playlist = CanonicalPlaylistEntity::find_by_id(state.canonical_playlist_id)
                .one(db)
                .await?
                .ok_or_else(|| anyhow!("Canonical playlist missing after refresh"))?;
            if canonical_playlist.match_status == "unresolved" {
                unresolved_playlists += 1;
            }
            canonical_playlist_ids.insert(state.canonical_playlist_id);
        }

        Ok(ProviderRefreshSummary {
            provider: provider.as_str().to_string(),
            tracks: provider_track_states.len(),
            albums: canonical_album_ids.len(),
            playlists: canonical_playlist_ids.len(),
            canonical_tracks: canonical_track_ids.len(),
            canonical_albums: canonical_album_ids.len(),
            canonical_playlists: canonical_playlist_ids.len(),
            unresolved_tracks,
            unresolved_albums,
            unresolved_playlists,
        })
    }

    pub async fn ensure_user_track_from_input(
        db: &DatabaseConnection,
        user_id: Uuid,
        provider: LibraryProvider,
        provider_track_id: &str,
        title: &str,
        artist: &str,
        album_name: Option<&str>,
        duration: Option<i32>,
        cover_url: Option<&str>,
    ) -> Result<crate::models::UserTrackModel> {
        let mut provider_track_states = HashMap::new();
        let track = StreamingTrack {
            id: provider_track_id.to_string(),
            title: title.to_string(),
            artist: artist.to_string(),
            album: album_name.unwrap_or_default().to_string(),
            duration,
            stream_url: None,
            cover_url: cover_url.map(|value| value.to_string()),
            quality: None,
            source: provider.as_str().to_string(),
            bitrate: None,
            sample_rate: None,
            bit_depth: None,
        };

        let state = ensure_provider_track_state(db, user_id, provider, &mut provider_track_states, &track).await?;
        materialize_user_track(db, user_id, provider, &state.track, state.canonical_track_id).await
    }

    pub async fn list_user_tracks(
        db: &DatabaseConnection,
        user_id: Uuid,
        search: Option<&str>,
        page: u64,
        limit: u64,
    ) -> Result<(Vec<UserTrackSummary>, u64)> {
        let mut query = UserTrackEntity::find().filter(UserTrackColumn::UserId.eq(user_id));
        if let Some(search_value) = search.filter(|value| !value.trim().is_empty()) {
            query = query.filter(
                UserTrackColumn::Title
                    .contains(search_value)
                    .or(UserTrackColumn::Artist.contains(search_value))
                    .or(UserTrackColumn::AlbumName.contains(search_value)),
            );
        }

        let total = query.clone().count(db).await?;
        let rows = query
            .order_by_asc(UserTrackColumn::Artist)
            .order_by_asc(UserTrackColumn::Title)
            .offset((page.saturating_sub(1)) * limit)
            .limit(limit)
            .all(db)
            .await?;

        Ok((rows.into_iter().map(user_track_summary).collect(), total))
    }

    pub async fn remove_user_track(db: &DatabaseConnection, user_id: Uuid, user_track_id: Uuid) -> Result<bool> {
        let result = UserTrackEntity::delete_many()
            .filter(UserTrackColumn::Id.eq(user_track_id))
            .filter(UserTrackColumn::UserId.eq(user_id))
            .exec(db)
            .await?;
        Ok(result.rows_affected > 0)
    }

    pub async fn is_track_saved(
        db: &DatabaseConnection,
        user_id: Uuid,
        provider: LibraryProvider,
        provider_track_id: &str,
    ) -> Result<bool> {
        let existing = UserTrackEntity::find()
            .filter(UserTrackColumn::UserId.eq(user_id))
            .filter(UserTrackColumn::Source.eq(provider.as_str()))
            .filter(UserTrackColumn::ProviderTrackId.eq(provider_track_id))
            .one(db)
            .await?;
        Ok(existing.is_some())
    }

    pub async fn import_canonical_playlist(
        db: &DatabaseConnection,
        user_id: Uuid,
        canonical_playlist_id: Uuid,
        preferred_source: Option<LibraryProvider>,
        watched: bool,
    ) -> Result<crate::models::UserPlaylistModel> {
        sync_user_playlist_from_canonical(db, user_id, None, canonical_playlist_id, preferred_source, watched).await
    }

    pub async fn import_provider_playlist(
        db: &DatabaseConnection,
        user_id: Uuid,
        provider: LibraryProvider,
        playlist: StreamingPlaylist,
        watched: bool,
    ) -> Result<crate::models::UserPlaylistModel> {
        let service = create_authenticated_streaming_service(provider, user_id, db).await?;
        let playlist_tracks = fetch_playlist_tracks(service.as_ref(), &playlist.id).await?;
        let mut provider_track_states: HashMap<String, ProviderTrackState> = HashMap::new();
        let provider_playlist_state = sync_provider_playlist(
            db,
            user_id,
            provider,
            &playlist,
            &playlist_tracks,
            &mut provider_track_states,
        )
        .await?;

        sync_user_playlist_from_canonical(
            db,
            user_id,
            None,
            provider_playlist_state.canonical_playlist_id,
            Some(provider),
            watched,
        )
        .await
    }

    pub async fn refresh_watched_playlist(
        db: &DatabaseConnection,
        user_id: Uuid,
        user_playlist_id: Uuid,
    ) -> Result<crate::models::UserPlaylistModel> {
        let user_playlist = UserPlaylistEntity::find_by_id(user_playlist_id)
            .filter(UserPlaylistColumn::UserId.eq(user_id))
            .one(db)
            .await?
            .ok_or_else(|| anyhow!("Playlist not found"))?;

        if !user_playlist.is_watched || !user_playlist.is_read_only {
            return Err(anyhow!("Only watched read-only playlists can be refreshed"));
        }

        let canonical_playlist_id = user_playlist
            .canonical_playlist_id
            .ok_or_else(|| anyhow!("Watched playlist is not linked to a canonical playlist"))?;
        let preferred_source = user_playlist
            .source
            .as_deref()
            .map(LibraryProvider::from_str)
            .transpose()?;

        sync_user_playlist_from_canonical(
            db,
            user_id,
            Some(user_playlist_id),
            canonical_playlist_id,
            preferred_source,
            true,
        )
        .await
    }

    pub async fn unresolved_matches(db: &DatabaseConnection) -> Result<UnresolvedMatchesResponse> {
        let tracks = CanonicalTrackEntity::find()
            .filter(CanonicalTrackColumn::MatchStatus.eq("unresolved"))
            .all(db)
            .await?;
        let albums = CanonicalAlbumEntity::find()
            .filter(CanonicalAlbumColumn::MatchStatus.eq("unresolved"))
            .all(db)
            .await?;
        let playlists = CanonicalPlaylistEntity::find()
            .filter(CanonicalPlaylistColumn::MatchStatus.eq("unresolved"))
            .all(db)
            .await?;

        Ok(UnresolvedMatchesResponse {
            tracks: tracks
                .into_iter()
                .map(|track| CanonicalMatchSummary {
                    id: track.id,
                    name: track.title,
                    artist_or_owner: Some(track.artist),
                    reason: track.unresolved_reason,
                })
                .collect(),
            albums: albums
                .into_iter()
                .map(|album| CanonicalMatchSummary {
                    id: album.id,
                    name: album.name,
                    artist_or_owner: Some(album.artist),
                    reason: album.unresolved_reason,
                })
                .collect(),
            playlists: playlists
                .into_iter()
                .map(|playlist| CanonicalMatchSummary {
                    id: playlist.id,
                    name: playlist.name,
                    artist_or_owner: playlist.owner_name,
                    reason: playlist.unresolved_reason,
                })
                .collect(),
        })
    }
}

fn user_track_summary(model: crate::models::UserTrackModel) -> UserTrackSummary {
    UserTrackSummary {
        id: model.id,
        canonical_track_id: model.canonical_track_id,
        provider_track_id: model.provider_track_id,
        source: model.source,
        title: model.title,
        artist: model.artist,
        album_name: model.album_name,
        duration: model.duration,
        cover_url: model.cover_url,
    }
}

async fn sync_user_playlist_from_canonical(
    db: &DatabaseConnection,
    user_id: Uuid,
    existing_user_playlist_id: Option<Uuid>,
    canonical_playlist_id: Uuid,
    preferred_source: Option<LibraryProvider>,
    watched: bool,
) -> Result<crate::models::UserPlaylistModel> {
    let canonical_playlist = CanonicalPlaylistEntity::find_by_id(canonical_playlist_id)
        .one(db)
        .await?
        .ok_or_else(|| anyhow!("Canonical playlist not found"))?;

    let source = match preferred_source {
        Some(source) => source,
        None => canonical_playlist_default_source(&canonical_playlist)
            .await
            .ok_or_else(|| anyhow!("Canonical playlist has no provider source attached"))?,
    };

    let provider_playlist_id = canonical_playlist_provider_id(db, &canonical_playlist, source)
        .await?
        .ok_or_else(|| anyhow!("Canonical playlist has no provider playlist for {}", source.as_str()))?;

    let playlist_model = if let Some(existing_id) = existing_user_playlist_id {
        let playlist = UserPlaylistEntity::find_by_id(existing_id)
            .filter(UserPlaylistColumn::UserId.eq(user_id))
            .one(db)
            .await?
            .ok_or_else(|| anyhow!("User playlist not found"))?;
        let mut active = playlist.into_active_model();
        active.canonical_playlist_id = Set(Some(canonical_playlist_id));
        active.source = Set(Some(source.as_str().to_string()));
        active.provider_playlist_id = Set(Some(provider_playlist_id.clone()));
        active.name = Set(canonical_playlist.name.clone());
        active.description = Set(canonical_playlist.description.clone());
        active.is_read_only = Set(true);
        active.is_watched = Set(watched);
        active.last_synced_at = Set(Some(chrono::Utc::now().naive_utc()));
        active.updated_at = Set(chrono::Utc::now().naive_utc());
        active.update(db).await?
    } else if let Some(existing) = UserPlaylistEntity::find()
        .filter(UserPlaylistColumn::UserId.eq(user_id))
        .filter(UserPlaylistColumn::CanonicalPlaylistId.eq(canonical_playlist_id))
        .one(db)
        .await?
    {
        let mut active = existing.into_active_model();
        active.source = Set(Some(source.as_str().to_string()));
        active.provider_playlist_id = Set(Some(provider_playlist_id.clone()));
        active.name = Set(canonical_playlist.name.clone());
        active.description = Set(canonical_playlist.description.clone());
        active.is_read_only = Set(true);
        active.is_watched = Set(watched);
        active.last_synced_at = Set(Some(chrono::Utc::now().naive_utc()));
        active.updated_at = Set(chrono::Utc::now().naive_utc());
        active.update(db).await?
    } else {
        UserPlaylistActiveModel {
            user_id: Set(user_id),
            canonical_playlist_id: Set(Some(canonical_playlist_id)),
            source: Set(Some(source.as_str().to_string())),
            provider_playlist_id: Set(Some(provider_playlist_id.clone())),
            name: Set(canonical_playlist.name.clone()),
            description: Set(canonical_playlist.description.clone()),
            is_public: Set(false),
            is_read_only: Set(true),
            is_watched: Set(watched),
            last_synced_at: Set(Some(chrono::Utc::now().naive_utc())),
            ..UserPlaylistActiveModel::new()
        }
        .insert(db)
        .await?
    };

    let playlist_tracks = CanonicalPlaylistTrackEntity::find()
        .filter(crate::models::CanonicalPlaylistTrackColumn::PlaylistId.eq(canonical_playlist_id))
        .order_by_asc(crate::models::CanonicalPlaylistTrackColumn::Position)
        .all(db)
        .await?;

    UserPlaylistItemEntity::delete_many()
        .filter(UserPlaylistItemColumn::PlaylistId.eq(playlist_model.id))
        .exec(db)
        .await?;

    for playlist_track in playlist_tracks {
        let canonical_track = CanonicalTrackEntity::find_by_id(playlist_track.canonical_track_id)
            .one(db)
            .await?
            .ok_or_else(|| anyhow!("Canonical playlist contains missing track"))?;
        let provider_reference = canonical_track_provider_reference(db, &canonical_track, Some(source)).await?
            .ok_or_else(|| anyhow!("Canonical track {} has no provider track for {}", canonical_track.id, source.as_str()))?;
        let user_track = materialize_user_track(
            db,
            user_id,
            provider_reference.source,
            &canonical_track_to_streaming_track(db, &canonical_track, &provider_reference).await?,
            canonical_track.id,
        )
        .await?;

        UserPlaylistItemActiveModel {
            playlist_id: Set(playlist_model.id),
            item_type: Set("track".to_string()),
            user_track_id: Set(Some(user_track.id)),
            nested_playlist_id: Set(None),
            position: Set(playlist_track.position),
            ..UserPlaylistItemActiveModel::new()
        }
        .insert(db)
        .await?;
    }

    Ok(playlist_model)
}

async fn fetch_library_tracks(service: &dyn StreamingService) -> Result<Vec<StreamingTrack>> {
    let mut offset = 0;
    let mut tracks = Vec::new();
    loop {
        let result = service.search_library("", Some("track"), Some(PAGE_SIZE), Some(offset)).await?;
        if result.tracks.is_empty() {
            break;
        }
        let count = result.tracks.len() as u32;
        tracks.extend(result.tracks);
        if count < PAGE_SIZE {
            break;
        }
        offset += count;
    }
    Ok(tracks)
}

async fn fetch_library_albums(service: &dyn StreamingService) -> Result<Vec<StreamingAlbum>> {
    let mut offset = 0;
    let mut albums = Vec::new();
    loop {
        let result = service.search_library("", Some("album"), Some(PAGE_SIZE), Some(offset)).await?;
        if result.albums.is_empty() {
            break;
        }
        let count = result.albums.len() as u32;
        albums.extend(result.albums);
        if count < PAGE_SIZE {
            break;
        }
        offset += count;
    }
    Ok(albums)
}

async fn fetch_library_playlists(service: &dyn StreamingService) -> Result<Vec<StreamingPlaylist>> {
    let mut offset = 0;
    let mut playlists = Vec::new();
    loop {
        let result = service.search_library("", Some("playlist"), Some(PAGE_SIZE), Some(offset)).await?;
        if result.playlists.is_empty() {
            break;
        }
        let count = result.playlists.len() as u32;
        playlists.extend(result.playlists);
        if count < PAGE_SIZE {
            break;
        }
        offset += count;
    }
    Ok(playlists)
}

async fn fetch_playlist_tracks(service: &dyn StreamingService, playlist_id: &str) -> Result<Vec<StreamingTrack>> {
    let mut offset = 0;
    let mut tracks = Vec::new();
    loop {
        let batch = service.get_playlist_tracks(playlist_id, Some(PAGE_SIZE), Some(offset)).await?;
        if batch.is_empty() {
            break;
        }
        let count = batch.len() as u32;
        tracks.extend(batch);
        if count < PAGE_SIZE {
            break;
        }
        offset += count;
    }
    Ok(tracks)
}

fn dedupe_tracks(tracks: Vec<StreamingTrack>) -> Vec<StreamingTrack> {
    let mut seen = HashSet::new();
    tracks
        .into_iter()
        .filter(|track| seen.insert(track.id.clone()))
        .collect()
}

async fn create_authenticated_streaming_service(
    provider: LibraryProvider,
    user_id: Uuid,
    db: &DatabaseConnection,
) -> Result<Box<dyn StreamingService>> {
    Ok(match provider {
        LibraryProvider::Spotify => {
            let client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
            let client_secret = std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default();
            let (access_token, refresh_token) = get_valid_spotify_tokens(user_id, db).await.map_err(anyhow::Error::msg)?;
            Box::new(SpotifyService::new(client_id, client_secret).with_tokens(access_token, refresh_token))
        }
        LibraryProvider::Tidal => {
            let client_id = std::env::var("TIDAL_CLIENT_ID").unwrap_or_default();
            let client_secret = std::env::var("TIDAL_CLIENT_SECRET").unwrap_or_default();
            let (access_token, refresh_token) = get_valid_tidal_tokens(user_id, db).await.map_err(anyhow::Error::msg)?;
            Box::new(TidalService::new(client_id, client_secret).with_tokens(access_token, refresh_token))
        }
        LibraryProvider::Qobuz => {
            let client_id = std::env::var("QOBUZ_APP_ID").unwrap_or_default();
            let client_secret = std::env::var("QOBUZ_SECRET").unwrap_or_default();
            let service = StreamingServiceEntity::find()
                .filter(StreamingServiceColumn::UserId.eq(user_id))
                .filter(StreamingServiceColumn::ServiceName.eq("qobuz"))
                .filter(StreamingServiceColumn::IsActive.eq(true))
                .one(db)
                .await?
                .ok_or_else(|| anyhow!("Qobuz service not connected"))?;
            let token = service.access_token.ok_or_else(|| anyhow!("No Qobuz access token configured"))?;
            Box::new(QobuzService::new(client_id, client_secret).with_auth_token(token))
        }
        LibraryProvider::Server => {
            let music_dir = std::env::current_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from("."))
                .join("own_music");
            Box::new(LocalMusicService::new(music_dir))
        }
    })
}

async fn clear_provider_cache(db: &DatabaseConnection, user_id: Uuid, provider: LibraryProvider) -> Result<()> {
    match provider {
        LibraryProvider::Spotify => {
            SpotifyPlaylistEntity::delete_many().filter(SpotifyPlaylistColumn::UserId.eq(user_id)).exec(db).await?;
            SpotifyAlbumEntity::delete_many().filter(SpotifyAlbumColumn::UserId.eq(user_id)).exec(db).await?;
            SpotifyTrackEntity::delete_many().filter(SpotifyTrackColumn::UserId.eq(user_id)).exec(db).await?;
        }
        LibraryProvider::Tidal => {
            TidalPlaylistEntity::delete_many().filter(TidalPlaylistColumn::UserId.eq(user_id)).exec(db).await?;
            TidalAlbumEntity::delete_many().filter(TidalAlbumColumn::UserId.eq(user_id)).exec(db).await?;
            TidalTrackEntity::delete_many().filter(TidalTrackColumn::UserId.eq(user_id)).exec(db).await?;
        }
        LibraryProvider::Qobuz => {
            QobuzPlaylistEntity::delete_many().filter(QobuzPlaylistColumn::UserId.eq(user_id)).exec(db).await?;
            QobuzAlbumEntity::delete_many().filter(QobuzAlbumColumn::UserId.eq(user_id)).exec(db).await?;
            QobuzTrackEntity::delete_many().filter(QobuzTrackColumn::UserId.eq(user_id)).exec(db).await?;
        }
        LibraryProvider::Server => {
            ServerPlaylistEntity::delete_many().filter(ServerPlaylistColumn::UserId.eq(user_id)).exec(db).await?;
            ServerAlbumEntity::delete_many().filter(ServerAlbumColumn::UserId.eq(user_id)).exec(db).await?;
            ServerTrackEntity::delete_many().filter(ServerTrackColumn::UserId.eq(user_id)).exec(db).await?;
        }
    }
    Ok(())
}

async fn ensure_provider_track_state(
    db: &DatabaseConnection,
    user_id: Uuid,
    provider: LibraryProvider,
    states: &mut HashMap<String, ProviderTrackState>,
    track: &StreamingTrack,
) -> Result<ProviderTrackState> {
    if let Some(existing) = states.get(&track.id) {
        return Ok(existing.clone());
    }

    let provider_row_id = ensure_provider_track_row(
        db,
        user_id,
        provider,
        TrackInput {
            provider_track_id: track.id.clone(),
            title: track.title.clone(),
            artist: track.artist.clone(),
            album_name: option_string(&track.album),
            duration: track.duration,
            cover_url: track.cover_url.clone(),
            provider_metadata: serde_json::to_value(track).unwrap_or(Value::Null),
        },
    )
    .await?;
    let canonical_track = reconcile_canonical_track(db, provider, provider_row_id, track).await?;
    let state = ProviderTrackState {
        provider_row_id,
        canonical_track_id: canonical_track.id,
        track: track.clone(),
    };
    states.insert(track.id.clone(), state.clone());
    Ok(state)
}

async fn ensure_provider_track_row(
    db: &DatabaseConnection,
    user_id: Uuid,
    provider: LibraryProvider,
    input: TrackInput,
) -> Result<Uuid> {
    match provider {
        LibraryProvider::Spotify => {
            if let Some(existing) = SpotifyTrackEntity::find()
                .filter(SpotifyTrackColumn::UserId.eq(user_id))
                .filter(SpotifyTrackColumn::ProviderTrackId.eq(&input.provider_track_id))
                .one(db)
                .await? {
                return Ok(existing.id);
            }
            Ok(SpotifyTrackActiveModel {
                user_id: Set(user_id),
                provider_track_id: Set(input.provider_track_id),
                title: Set(input.title),
                artist: Set(input.artist),
                album_name: Set(input.album_name),
                duration: Set(input.duration),
                cover_url: Set(input.cover_url),
                provider_metadata: Set(input.provider_metadata),
                ..SpotifyTrackActiveModel::new()
            }
            .insert(db)
            .await?
            .id)
        }
        LibraryProvider::Tidal => {
            if let Some(existing) = TidalTrackEntity::find()
                .filter(TidalTrackColumn::UserId.eq(user_id))
                .filter(TidalTrackColumn::ProviderTrackId.eq(&input.provider_track_id))
                .one(db)
                .await? {
                return Ok(existing.id);
            }
            Ok(TidalTrackActiveModel {
                user_id: Set(user_id),
                provider_track_id: Set(input.provider_track_id),
                title: Set(input.title),
                artist: Set(input.artist),
                album_name: Set(input.album_name),
                duration: Set(input.duration),
                cover_url: Set(input.cover_url),
                provider_metadata: Set(input.provider_metadata),
                ..TidalTrackActiveModel::new()
            }
            .insert(db)
            .await?
            .id)
        }
        LibraryProvider::Qobuz => {
            if let Some(existing) = QobuzTrackEntity::find()
                .filter(QobuzTrackColumn::UserId.eq(user_id))
                .filter(QobuzTrackColumn::ProviderTrackId.eq(&input.provider_track_id))
                .one(db)
                .await? {
                return Ok(existing.id);
            }
            Ok(QobuzTrackActiveModel {
                user_id: Set(user_id),
                provider_track_id: Set(input.provider_track_id),
                title: Set(input.title),
                artist: Set(input.artist),
                album_name: Set(input.album_name),
                duration: Set(input.duration),
                cover_url: Set(input.cover_url),
                provider_metadata: Set(input.provider_metadata),
                ..QobuzTrackActiveModel::new()
            }
            .insert(db)
            .await?
            .id)
        }
        LibraryProvider::Server => {
            if let Some(existing) = ServerTrackEntity::find()
                .filter(ServerTrackColumn::UserId.eq(user_id))
                .filter(ServerTrackColumn::ProviderTrackId.eq(&input.provider_track_id))
                .one(db)
                .await? {
                return Ok(existing.id);
            }
            Ok(ServerTrackActiveModel {
                user_id: Set(user_id),
                provider_track_id: Set(input.provider_track_id),
                title: Set(input.title),
                artist: Set(input.artist),
                album_name: Set(input.album_name),
                duration: Set(input.duration),
                cover_url: Set(input.cover_url),
                provider_metadata: Set(input.provider_metadata),
                ..ServerTrackActiveModel::new()
            }
            .insert(db)
            .await?
            .id)
        }
    }
}

async fn sync_provider_album(
    db: &DatabaseConnection,
    user_id: Uuid,
    provider: LibraryProvider,
    album: &StreamingAlbum,
    album_tracks: &[StreamingTrack],
    provider_track_states: &mut HashMap<String, ProviderTrackState>,
) -> Result<ProviderAlbumState> {
    let mut album_member_rows = Vec::new();
    let mut canonical_track_ids = Vec::new();
    for track in album_tracks.iter().cloned() {
        let state = ensure_provider_track_state(db, user_id, provider, provider_track_states, &track).await?;
        album_member_rows.push(state.provider_row_id);
        canonical_track_ids.push(state.canonical_track_id);
    }

    let track_signature = album_signature(album_tracks);
    let provider_album_id = insert_provider_album_row(db, user_id, provider, album, track_signature.clone()).await?;
    sync_provider_album_tracks(db, provider, provider_album_id, &album_member_rows).await?;
    let canonical_album = reconcile_canonical_album(db, provider, provider_album_id, album, track_signature.clone()).await?;
    sync_canonical_album_tracks(db, canonical_album.id, &canonical_track_ids).await?;
    Ok(ProviderAlbumState { canonical_album_id: canonical_album.id })
}

async fn sync_provider_playlist(
    db: &DatabaseConnection,
    user_id: Uuid,
    provider: LibraryProvider,
    playlist: &StreamingPlaylist,
    playlist_tracks: &[StreamingTrack],
    provider_track_states: &mut HashMap<String, ProviderTrackState>,
) -> Result<ProviderPlaylistState> {
    let mut provider_track_ids = Vec::new();
    let mut canonical_track_ids = Vec::new();
    for track in playlist_tracks.iter().cloned() {
        let state = ensure_provider_track_state(db, user_id, provider, provider_track_states, &track).await?;
        provider_track_ids.push(state.provider_row_id);
        canonical_track_ids.push(state.canonical_track_id);
    }

    let content_signature = playlist_signature(playlist_tracks);
    let provider_playlist_id = insert_provider_playlist_row(db, user_id, provider, playlist, content_signature.clone()).await?;
    sync_provider_playlist_tracks(db, provider, provider_playlist_id, &provider_track_ids).await?;
    let canonical_playlist = reconcile_canonical_playlist(db, provider, provider_playlist_id, playlist, content_signature.clone()).await?;
    sync_canonical_playlist_tracks(db, canonical_playlist.id, &canonical_track_ids).await?;
    Ok(ProviderPlaylistState { canonical_playlist_id: canonical_playlist.id })
}

async fn insert_provider_album_row(
    db: &DatabaseConnection,
    user_id: Uuid,
    provider: LibraryProvider,
    album: &StreamingAlbum,
    track_signature: Option<String>,
) -> Result<Uuid> {
    let metadata = serde_json::to_value(album).unwrap_or(Value::Null);
    match provider {
        LibraryProvider::Spotify => Ok(SpotifyAlbumActiveModel {
            user_id: Set(user_id),
            provider_album_id: Set(album.id.clone()),
            name: Set(album.title.clone()),
            artist: Set(album.artist.clone()),
            track_signature: Set(track_signature),
            release_date: Set(album.release_date.clone()),
            cover_url: Set(album.cover_url.clone()),
            track_count: Set(Some(album.tracks.len() as i32)),
            provider_metadata: Set(metadata),
            ..SpotifyAlbumActiveModel::new()
        }.insert(db).await?.id),
        LibraryProvider::Tidal => Ok(TidalAlbumActiveModel {
            user_id: Set(user_id), provider_album_id: Set(album.id.clone()), name: Set(album.title.clone()), artist: Set(album.artist.clone()), track_signature: Set(track_signature), release_date: Set(album.release_date.clone()), cover_url: Set(album.cover_url.clone()), track_count: Set(Some(album.tracks.len() as i32)), provider_metadata: Set(metadata), ..TidalAlbumActiveModel::new()
        }.insert(db).await?.id),
        LibraryProvider::Qobuz => Ok(QobuzAlbumActiveModel {
            user_id: Set(user_id), provider_album_id: Set(album.id.clone()), name: Set(album.title.clone()), artist: Set(album.artist.clone()), track_signature: Set(track_signature), release_date: Set(album.release_date.clone()), cover_url: Set(album.cover_url.clone()), track_count: Set(Some(album.tracks.len() as i32)), provider_metadata: Set(metadata), ..QobuzAlbumActiveModel::new()
        }.insert(db).await?.id),
        LibraryProvider::Server => Ok(ServerAlbumActiveModel {
            user_id: Set(user_id), provider_album_id: Set(album.id.clone()), name: Set(album.title.clone()), artist: Set(album.artist.clone()), track_signature: Set(track_signature), release_date: Set(album.release_date.clone()), cover_url: Set(album.cover_url.clone()), track_count: Set(Some(album.tracks.len() as i32)), provider_metadata: Set(metadata), ..ServerAlbumActiveModel::new()
        }.insert(db).await?.id),
    }
}

async fn insert_provider_playlist_row(
    db: &DatabaseConnection,
    user_id: Uuid,
    provider: LibraryProvider,
    playlist: &StreamingPlaylist,
    content_signature: Option<String>,
) -> Result<Uuid> {
    let metadata = serde_json::to_value(playlist).unwrap_or(Value::Null);
    match provider {
        LibraryProvider::Spotify => Ok(SpotifyPlaylistActiveModel {
            user_id: Set(user_id), provider_playlist_id: Set(playlist.id.clone()), name: Set(playlist.name.clone()), description: Set(playlist.description.clone()), owner_name: Set(option_string(&playlist.owner)), content_signature: Set(content_signature), cover_url: Set(playlist.cover_url.clone()), provider_metadata: Set(metadata), ..SpotifyPlaylistActiveModel::new()
        }.insert(db).await?.id),
        LibraryProvider::Tidal => Ok(TidalPlaylistActiveModel {
            user_id: Set(user_id), provider_playlist_id: Set(playlist.id.clone()), name: Set(playlist.name.clone()), description: Set(playlist.description.clone()), owner_name: Set(option_string(&playlist.owner)), content_signature: Set(content_signature), cover_url: Set(playlist.cover_url.clone()), provider_metadata: Set(metadata), ..TidalPlaylistActiveModel::new()
        }.insert(db).await?.id),
        LibraryProvider::Qobuz => Ok(QobuzPlaylistActiveModel {
            user_id: Set(user_id), provider_playlist_id: Set(playlist.id.clone()), name: Set(playlist.name.clone()), description: Set(playlist.description.clone()), owner_name: Set(option_string(&playlist.owner)), content_signature: Set(content_signature), cover_url: Set(playlist.cover_url.clone()), provider_metadata: Set(metadata), ..QobuzPlaylistActiveModel::new()
        }.insert(db).await?.id),
        LibraryProvider::Server => Ok(ServerPlaylistActiveModel {
            user_id: Set(user_id), provider_playlist_id: Set(playlist.id.clone()), name: Set(playlist.name.clone()), description: Set(playlist.description.clone()), owner_name: Set(option_string(&playlist.owner)), content_signature: Set(content_signature), cover_url: Set(playlist.cover_url.clone()), provider_metadata: Set(metadata), ..ServerPlaylistActiveModel::new()
        }.insert(db).await?.id),
    }
}

async fn sync_provider_album_tracks(db: &DatabaseConnection, provider: LibraryProvider, album_id: Uuid, track_ids: &[Uuid]) -> Result<()> {
    match provider {
        LibraryProvider::Spotify => {
            for (position, track_id) in track_ids.iter().enumerate() {
                SpotifyAlbumTrackActiveModel { album_id: Set(album_id), track_id: Set(*track_id), position: Set(position as i32), ..SpotifyAlbumTrackActiveModel::new() }.insert(db).await?;
            }
        }
        LibraryProvider::Tidal => {
            for (position, track_id) in track_ids.iter().enumerate() {
                TidalAlbumTrackActiveModel { album_id: Set(album_id), track_id: Set(*track_id), position: Set(position as i32), ..TidalAlbumTrackActiveModel::new() }.insert(db).await?;
            }
        }
        LibraryProvider::Qobuz => {
            for (position, track_id) in track_ids.iter().enumerate() {
                QobuzAlbumTrackActiveModel { album_id: Set(album_id), track_id: Set(*track_id), position: Set(position as i32), ..QobuzAlbumTrackActiveModel::new() }.insert(db).await?;
            }
        }
        LibraryProvider::Server => {
            for (position, track_id) in track_ids.iter().enumerate() {
                ServerAlbumTrackActiveModel { album_id: Set(album_id), track_id: Set(*track_id), position: Set(position as i32), ..ServerAlbumTrackActiveModel::new() }.insert(db).await?;
            }
        }
    }
    Ok(())
}

async fn sync_provider_playlist_tracks(db: &DatabaseConnection, provider: LibraryProvider, playlist_id: Uuid, track_ids: &[Uuid]) -> Result<()> {
    match provider {
        LibraryProvider::Spotify => {
            for (position, track_id) in track_ids.iter().enumerate() {
                SpotifyPlaylistTrackActiveModel { playlist_id: Set(playlist_id), track_id: Set(*track_id), position: Set(position as i32), ..SpotifyPlaylistTrackActiveModel::new() }.insert(db).await?;
            }
        }
        LibraryProvider::Tidal => {
            for (position, track_id) in track_ids.iter().enumerate() {
                TidalPlaylistTrackActiveModel { playlist_id: Set(playlist_id), track_id: Set(*track_id), position: Set(position as i32), ..TidalPlaylistTrackActiveModel::new() }.insert(db).await?;
            }
        }
        LibraryProvider::Qobuz => {
            for (position, track_id) in track_ids.iter().enumerate() {
                QobuzPlaylistTrackActiveModel { playlist_id: Set(playlist_id), track_id: Set(*track_id), position: Set(position as i32), ..QobuzPlaylistTrackActiveModel::new() }.insert(db).await?;
            }
        }
        LibraryProvider::Server => {
            for (position, track_id) in track_ids.iter().enumerate() {
                ServerPlaylistTrackActiveModel { playlist_id: Set(playlist_id), track_id: Set(*track_id), position: Set(position as i32), ..ServerPlaylistTrackActiveModel::new() }.insert(db).await?;
            }
        }
    }
    Ok(())
}

async fn reconcile_canonical_track(
    db: &DatabaseConnection,
    provider: LibraryProvider,
    provider_row_id: Uuid,
    track: &StreamingTrack,
) -> Result<crate::models::CanonicalTrackModel> {
    let normalized_title = normalize_text(&track.title);
    let normalized_artist = normalize_text(&track.artist);
    let matches = CanonicalTrackEntity::find()
        .filter(CanonicalTrackColumn::NormalizedTitle.eq(&normalized_title))
        .filter(CanonicalTrackColumn::NormalizedArtist.eq(&normalized_artist))
        .all(db)
        .await?;

    if matches.len() == 1 {
        let mut active = matches.into_iter().next().unwrap().into_active_model();
        set_canonical_track_provider_link(&mut active, provider, Some(provider_row_id));
        active.title = Set(track.title.clone());
        active.artist = Set(track.artist.clone());
        active.album_name = Set(option_string(&track.album));
        active.duration = Set(track.duration);
        active.cover_url = Set(track.cover_url.clone());
        active.match_status = Set("resolved".to_string());
        active.unresolved_reason = Set(None);
        return Ok(active.update(db).await?);
    }

    let mut active = CanonicalTrackActiveModel {
        title: Set(track.title.clone()),
        artist: Set(track.artist.clone()),
        album_name: Set(option_string(&track.album)),
        duration: Set(track.duration),
        cover_url: Set(track.cover_url.clone()),
        normalized_title: Set(normalized_title),
        normalized_artist: Set(normalized_artist),
        match_status: Set(if matches.is_empty() { "resolved".to_string() } else { "unresolved".to_string() }),
        unresolved_reason: Set(if matches.is_empty() { None } else { Some("Multiple canonical tracks matched by title and artist".to_string()) }),
        ..CanonicalTrackActiveModel::new()
    };
    set_canonical_track_provider_link(&mut active, provider, Some(provider_row_id));
    active.insert(db).await.map_err(Into::into)
}

async fn reconcile_canonical_album(
    db: &DatabaseConnection,
    provider: LibraryProvider,
    provider_row_id: Uuid,
    album: &StreamingAlbum,
    track_signature: Option<String>,
) -> Result<crate::models::CanonicalAlbumModel> {
    let normalized_name = normalize_text(&album.title);
    let normalized_artist = normalize_text(&album.artist);
    let candidates = CanonicalAlbumEntity::find()
        .filter(CanonicalAlbumColumn::NormalizedName.eq(&normalized_name))
        .filter(CanonicalAlbumColumn::NormalizedArtist.eq(&normalized_artist))
        .all(db)
        .await?;
    let exact_matches: Vec<_> = candidates
        .into_iter()
        .filter(|candidate| candidate.track_signature == track_signature)
        .collect();

    if exact_matches.len() == 1 {
        let mut active = exact_matches.into_iter().next().unwrap().into_active_model();
        set_canonical_album_provider_link(&mut active, provider, Some(provider_row_id));
        active.name = Set(album.title.clone());
        active.artist = Set(album.artist.clone());
        active.track_signature = Set(track_signature);
        active.release_date = Set(album.release_date.clone());
        active.cover_url = Set(album.cover_url.clone());
        active.match_status = Set("resolved".to_string());
        active.unresolved_reason = Set(None);
        return Ok(active.update(db).await?);
    }

    let mut active = CanonicalAlbumActiveModel {
        name: Set(album.title.clone()),
        artist: Set(album.artist.clone()),
        track_signature: Set(track_signature),
        release_date: Set(album.release_date.clone()),
        cover_url: Set(album.cover_url.clone()),
        normalized_name: Set(normalized_name),
        normalized_artist: Set(normalized_artist),
        match_status: Set(if exact_matches.is_empty() && !candidates_with_same_name_artist(db, &album.title, &album.artist).await? { "resolved".to_string() } else { "unresolved".to_string() }),
        unresolved_reason: Set(if exact_matches.is_empty() && !candidates_with_same_name_artist(db, &album.title, &album.artist).await? { None } else { Some("Multiple canonical albums matched by title, artist, and track signature".to_string()) }),
        ..CanonicalAlbumActiveModel::new()
    };
    set_canonical_album_provider_link(&mut active, provider, Some(provider_row_id));
    active.insert(db).await.map_err(Into::into)
}

async fn candidates_with_same_name_artist(db: &DatabaseConnection, name: &str, artist: &str) -> Result<bool> {
    let count = CanonicalAlbumEntity::find()
        .filter(CanonicalAlbumColumn::NormalizedName.eq(normalize_text(name)))
        .filter(CanonicalAlbumColumn::NormalizedArtist.eq(normalize_text(artist)))
        .count(db)
        .await?;
    Ok(count > 0)
}

async fn reconcile_canonical_playlist(
    db: &DatabaseConnection,
    provider: LibraryProvider,
    provider_row_id: Uuid,
    playlist: &StreamingPlaylist,
    content_signature: Option<String>,
) -> Result<crate::models::CanonicalPlaylistModel> {
    let normalized_name = normalize_text(&playlist.name);
    let candidates = CanonicalPlaylistEntity::find()
        .filter(CanonicalPlaylistColumn::NormalizedName.eq(&normalized_name))
        .all(db)
        .await?;
    let has_candidates = !candidates.is_empty();
    let exact_matches: Vec<_> = candidates
        .iter()
        .cloned()
        .filter(|candidate| candidate.content_signature == content_signature)
        .collect();

    if exact_matches.len() == 1 {
        let mut active = exact_matches.into_iter().next().unwrap().into_active_model();
        set_canonical_playlist_provider_link(&mut active, provider, Some(provider_row_id));
        active.name = Set(playlist.name.clone());
        active.description = Set(playlist.description.clone());
        active.owner_name = Set(option_string(&playlist.owner));
        active.content_signature = Set(content_signature);
        active.match_status = Set("resolved".to_string());
        active.unresolved_reason = Set(None);
        return Ok(active.update(db).await?);
    }

    let mut active = CanonicalPlaylistActiveModel {
        name: Set(playlist.name.clone()),
        description: Set(playlist.description.clone()),
        owner_name: Set(option_string(&playlist.owner)),
        normalized_name: Set(normalized_name),
        content_signature: Set(content_signature),
        match_status: Set(if exact_matches.is_empty() && !has_candidates { "resolved".to_string() } else { "unresolved".to_string() }),
        unresolved_reason: Set(if exact_matches.is_empty() && !has_candidates { None } else { Some("Multiple canonical playlists matched by name and ordered content".to_string()) }),
        ..CanonicalPlaylistActiveModel::new()
    };
    set_canonical_playlist_provider_link(&mut active, provider, Some(provider_row_id));
    active.insert(db).await.map_err(Into::into)
}

async fn sync_canonical_album_tracks(db: &DatabaseConnection, canonical_album_id: Uuid, canonical_track_ids: &[Uuid]) -> Result<()> {
    CanonicalAlbumTrackEntity::delete_many()
        .filter(crate::models::CanonicalAlbumTrackColumn::AlbumId.eq(canonical_album_id))
        .exec(db)
        .await?;
    for (position, track_id) in canonical_track_ids.iter().enumerate() {
        CanonicalAlbumTrackActiveModel { album_id: Set(canonical_album_id), canonical_track_id: Set(*track_id), position: Set(position as i32), ..CanonicalAlbumTrackActiveModel::new() }
            .insert(db)
            .await?;
    }
    Ok(())
}

async fn sync_canonical_playlist_tracks(db: &DatabaseConnection, canonical_playlist_id: Uuid, canonical_track_ids: &[Uuid]) -> Result<()> {
    CanonicalPlaylistTrackEntity::delete_many()
        .filter(crate::models::CanonicalPlaylistTrackColumn::PlaylistId.eq(canonical_playlist_id))
        .exec(db)
        .await?;
    for (position, track_id) in canonical_track_ids.iter().enumerate() {
        CanonicalPlaylistTrackActiveModel { playlist_id: Set(canonical_playlist_id), canonical_track_id: Set(*track_id), position: Set(position as i32), ..CanonicalPlaylistTrackActiveModel::new() }
            .insert(db)
            .await?;
    }
    Ok(())
}

async fn materialize_user_track(
    db: &DatabaseConnection,
    user_id: Uuid,
    provider: LibraryProvider,
    track: &StreamingTrack,
    canonical_track_id: Uuid,
) -> Result<crate::models::UserTrackModel> {
    if let Some(existing) = UserTrackEntity::find()
        .filter(UserTrackColumn::UserId.eq(user_id))
        .filter(UserTrackColumn::Source.eq(provider.as_str()))
        .filter(UserTrackColumn::ProviderTrackId.eq(&track.id))
        .one(db)
        .await? {
        let mut active = existing.into_active_model();
        active.canonical_track_id = Set(canonical_track_id);
        active.title = Set(track.title.clone());
        active.artist = Set(track.artist.clone());
        active.album_name = Set(option_string(&track.album));
        active.duration = Set(track.duration);
        active.cover_url = Set(track.cover_url.clone());
        active.updated_at = Set(chrono::Utc::now().naive_utc());
        return active.update(db).await.map_err(Into::into);
    }

    UserTrackActiveModel {
        user_id: Set(user_id),
        canonical_track_id: Set(canonical_track_id),
        source: Set(provider.as_str().to_string()),
        provider_track_id: Set(track.id.clone()),
        title: Set(track.title.clone()),
        artist: Set(track.artist.clone()),
        album_name: Set(option_string(&track.album)),
        duration: Set(track.duration),
        cover_url: Set(track.cover_url.clone()),
        ..UserTrackActiveModel::new()
    }
    .insert(db)
    .await
    .map_err(Into::into)
}

async fn canonical_track_provider_reference(
    db: &DatabaseConnection,
    canonical_track: &crate::models::CanonicalTrackModel,
    preferred_source: Option<LibraryProvider>,
) -> Result<Option<ProviderTrackReference>> {
    if let Some(source) = preferred_source {
        if let Some(reference) = provider_track_reference_by_source(db, canonical_track, source).await? {
            return Ok(Some(reference));
        }
    }

    for source in [LibraryProvider::Spotify, LibraryProvider::Tidal, LibraryProvider::Qobuz, LibraryProvider::Server] {
        if let Some(reference) = provider_track_reference_by_source(db, canonical_track, source).await? {
            return Ok(Some(reference));
        }
    }
    Ok(None)
}

async fn provider_track_reference_by_source(
    db: &DatabaseConnection,
    canonical_track: &crate::models::CanonicalTrackModel,
    source: LibraryProvider,
) -> Result<Option<ProviderTrackReference>> {
    let provider_track_id = match source {
        LibraryProvider::Spotify => match canonical_track.spotify_track_id {
            Some(id) => SpotifyTrackEntity::find_by_id(id).one(db).await?.map(|row| row.provider_track_id),
            None => None,
        },
        LibraryProvider::Tidal => match canonical_track.tidal_track_id {
            Some(id) => TidalTrackEntity::find_by_id(id).one(db).await?.map(|row| row.provider_track_id),
            None => None,
        },
        LibraryProvider::Qobuz => match canonical_track.qobuz_track_id {
            Some(id) => QobuzTrackEntity::find_by_id(id).one(db).await?.map(|row| row.provider_track_id),
            None => None,
        },
        LibraryProvider::Server => match canonical_track.server_track_id {
            Some(id) => ServerTrackEntity::find_by_id(id).one(db).await?.map(|row| row.provider_track_id),
            None => None,
        },
    };

    Ok(provider_track_id.map(|provider_track_id| ProviderTrackReference { source, provider_track_id }))
}

async fn canonical_playlist_default_source(canonical_playlist: &crate::models::CanonicalPlaylistModel) -> Option<LibraryProvider> {
    if canonical_playlist.spotify_playlist_id.is_some() { return Some(LibraryProvider::Spotify); }
    if canonical_playlist.tidal_playlist_id.is_some() { return Some(LibraryProvider::Tidal); }
    if canonical_playlist.qobuz_playlist_id.is_some() { return Some(LibraryProvider::Qobuz); }
    if canonical_playlist.server_playlist_id.is_some() { return Some(LibraryProvider::Server); }
    None
}

async fn canonical_playlist_provider_id(
    db: &DatabaseConnection,
    canonical_playlist: &crate::models::CanonicalPlaylistModel,
    source: LibraryProvider,
) -> Result<Option<String>> {
    Ok(match source {
        LibraryProvider::Spotify => match canonical_playlist.spotify_playlist_id { Some(id) => SpotifyPlaylistEntity::find_by_id(id).one(db).await?.map(|row| row.provider_playlist_id), None => None },
        LibraryProvider::Tidal => match canonical_playlist.tidal_playlist_id { Some(id) => TidalPlaylistEntity::find_by_id(id).one(db).await?.map(|row| row.provider_playlist_id), None => None },
        LibraryProvider::Qobuz => match canonical_playlist.qobuz_playlist_id { Some(id) => QobuzPlaylistEntity::find_by_id(id).one(db).await?.map(|row| row.provider_playlist_id), None => None },
        LibraryProvider::Server => match canonical_playlist.server_playlist_id { Some(id) => ServerPlaylistEntity::find_by_id(id).one(db).await?.map(|row| row.provider_playlist_id), None => None },
    })
}

async fn canonical_track_to_streaming_track(
    db: &DatabaseConnection,
    canonical_track: &crate::models::CanonicalTrackModel,
    reference: &ProviderTrackReference,
) -> Result<StreamingTrack> {
    let track = match reference.source {
        LibraryProvider::Spotify => SpotifyTrackEntity::find()
            .filter(SpotifyTrackColumn::ProviderTrackId.eq(&reference.provider_track_id))
            .one(db)
            .await?
            .map(|row| StreamingTrack { id: row.provider_track_id, title: row.title, artist: row.artist, album: row.album_name.unwrap_or_default(), duration: row.duration, stream_url: None, cover_url: row.cover_url, quality: None, source: "spotify".to_string(), bitrate: None, sample_rate: None, bit_depth: None }),
        LibraryProvider::Tidal => TidalTrackEntity::find()
            .filter(TidalTrackColumn::ProviderTrackId.eq(&reference.provider_track_id))
            .one(db)
            .await?
            .map(|row| StreamingTrack { id: row.provider_track_id, title: row.title, artist: row.artist, album: row.album_name.unwrap_or_default(), duration: row.duration, stream_url: None, cover_url: row.cover_url, quality: None, source: "tidal".to_string(), bitrate: None, sample_rate: None, bit_depth: None }),
        LibraryProvider::Qobuz => QobuzTrackEntity::find()
            .filter(QobuzTrackColumn::ProviderTrackId.eq(&reference.provider_track_id))
            .one(db)
            .await?
            .map(|row| StreamingTrack { id: row.provider_track_id, title: row.title, artist: row.artist, album: row.album_name.unwrap_or_default(), duration: row.duration, stream_url: None, cover_url: row.cover_url, quality: None, source: "qobuz".to_string(), bitrate: None, sample_rate: None, bit_depth: None }),
        LibraryProvider::Server => ServerTrackEntity::find()
            .filter(ServerTrackColumn::ProviderTrackId.eq(&reference.provider_track_id))
            .one(db)
            .await?
            .map(|row| StreamingTrack { id: row.provider_track_id, title: row.title, artist: row.artist, album: row.album_name.unwrap_or_default(), duration: row.duration, stream_url: None, cover_url: row.cover_url, quality: None, source: "server".to_string(), bitrate: None, sample_rate: None, bit_depth: None }),
    };
    track.ok_or_else(|| anyhow!("Provider track missing for canonical track {}", canonical_track.id))
}

fn normalize_text(value: &str) -> String {
    value
        .trim()
        .to_lowercase()
        .chars()
        .map(|character| if character.is_alphanumeric() { character } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn album_signature(tracks: &[StreamingTrack]) -> Option<String> {
    let mut parts = tracks
        .iter()
        .map(|track| normalize_text(&track.title))
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    if parts.is_empty() {
        return None;
    }
    parts.sort();
    Some(parts.join("|"))
}

fn playlist_signature(tracks: &[StreamingTrack]) -> Option<String> {
    let parts = tracks
        .iter()
        .map(|track| format!("{}::{}", normalize_text(&track.artist), normalize_text(&track.title)))
        .collect::<Vec<_>>();
    if parts.is_empty() {
        None
    } else {
        Some(parts.join("|"))
    }
}

fn option_string(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn set_canonical_track_provider_link(active: &mut CanonicalTrackActiveModel, provider: LibraryProvider, id: Option<Uuid>) {
    match provider {
        LibraryProvider::Spotify => active.spotify_track_id = Set(id),
        LibraryProvider::Tidal => active.tidal_track_id = Set(id),
        LibraryProvider::Qobuz => active.qobuz_track_id = Set(id),
        LibraryProvider::Server => active.server_track_id = Set(id),
    }
}

fn set_canonical_album_provider_link(active: &mut CanonicalAlbumActiveModel, provider: LibraryProvider, id: Option<Uuid>) {
    match provider {
        LibraryProvider::Spotify => active.spotify_album_id = Set(id),
        LibraryProvider::Tidal => active.tidal_album_id = Set(id),
        LibraryProvider::Qobuz => active.qobuz_album_id = Set(id),
        LibraryProvider::Server => active.server_album_id = Set(id),
    }
}

fn set_canonical_playlist_provider_link(active: &mut CanonicalPlaylistActiveModel, provider: LibraryProvider, id: Option<Uuid>) {
    match provider {
        LibraryProvider::Spotify => active.spotify_playlist_id = Set(id),
        LibraryProvider::Tidal => active.tidal_playlist_id = Set(id),
        LibraryProvider::Qobuz => active.qobuz_playlist_id = Set(id),
        LibraryProvider::Server => active.server_playlist_id = Set(id),
    }
}