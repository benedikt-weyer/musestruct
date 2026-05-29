use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    handlers::auth::{ApiResponse, AppState},
    models::{UserResponseDto, UserTrackColumn, UserTrackEntity, UserTrackModel},
    services::{
        LibraryProvider, LibrarySyncService, ServerPreloadMode, ServerPreloadProgress,
        UnresolvedMatchesResponse,
        cache_cover_url,
    },
};

#[derive(Deserialize, Debug)]
pub struct SaveTrackRequest {
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: i32,
    pub source: String,
    pub cover_url: Option<String>,
}

#[derive(Serialize)]
pub struct SavedTrackResponse {
    pub id: Uuid,
    pub canonical_track_id: Uuid,
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<i32>,
    pub source: String,
    pub cover_url: Option<String>,
    pub is_favourite: bool,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
}

#[derive(Serialize)]
pub struct FavouriteTrackResponse {
    pub id: Uuid,
    pub user_track_id: Uuid,
    pub canonical_track_id: Uuid,
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<i32>,
    pub source: String,
    pub cover_url: Option<String>,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
}

#[derive(Serialize)]
pub struct SavedTracksListResponse {
    pub tracks: Vec<SavedTrackResponse>,
    pub total_count: u64,
    pub page: u64,
    pub limit: u64,
}

#[derive(Serialize)]
pub struct FavouriteTracksListResponse {
    pub tracks: Vec<FavouriteTrackResponse>,
    pub total_count: u64,
    pub page: u64,
    pub limit: u64,
}

#[derive(Serialize)]
pub struct LastPlayedTrackResponse {
    pub id: Uuid,
    pub canonical_track_id: Uuid,
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<i32>,
    pub source: String,
    pub cover_url: Option<String>,
    pub played_at: chrono::NaiveDateTime,
    pub created_at: chrono::NaiveDateTime,
    pub updated_at: chrono::NaiveDateTime,
}

#[derive(Serialize)]
pub struct LastPlayedTracksListResponse {
    pub tracks: Vec<LastPlayedTrackResponse>,
    pub limit: u64,
}

#[derive(Deserialize)]
pub struct GetSavedTracksQuery {
    pub page: Option<u64>,
    pub limit: Option<u64>,
    pub search: Option<String>,
}

#[derive(Deserialize)]
pub struct GetLastPlayedTracksQuery {
    pub limit: Option<u64>,
}

#[derive(Deserialize)]
pub struct RecordLastPlayedTrackRequest {
    pub user_track_id: Uuid,
}

#[derive(Serialize)]
pub struct RefreshProviderResponse {
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

#[derive(Deserialize)]
pub struct StartServerPreloadRequest {
    pub mode: String,
}

pub async fn save_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<SaveTrackRequest>,
) -> Result<Json<ApiResponse<SavedTrackResponse>>, StatusCode> {
    let provider = request
        .source
        .parse::<LibraryProvider>()
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    let track = LibrarySyncService::ensure_user_track_from_input(
        state.db(),
        user.id,
        provider,
        &request.track_id,
        &request.title,
        &request.artist,
        Some(&request.album),
        Some(request.duration),
        request.cover_url.as_deref(),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let is_favourite = LibrarySyncService::is_track_favourite(
        state.db(),
        user.id,
        provider,
        &request.track_id,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(saved_track_response(track, is_favourite))))
}

pub async fn get_saved_tracks(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetSavedTracksQuery>,
) -> Result<Json<ApiResponse<SavedTracksListResponse>>, StatusCode> {
    let page = params.page.unwrap_or(1);
    let limit = params.limit.unwrap_or(50).min(100);

    let (track_summaries, total_count) = LibrarySyncService::list_user_tracks(
        state.db(),
        user.id,
        params.search.as_deref(),
        page,
        limit,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let favourite_by_track_id = track_summaries
        .iter()
        .map(|track| (track.id, track.is_favourite))
        .collect::<std::collections::HashMap<_, _>>();
    let track_ids = track_summaries.iter().map(|track| track.id).collect::<Vec<_>>();
    let tracks = UserTrackEntity::find()
        .filter(UserTrackColumn::UserId.eq(user.id))
        .filter(UserTrackColumn::Id.is_in(track_ids))
        .all(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .into_iter()
        .map(|track| {
            let is_favourite = favourite_by_track_id.get(&track.id).copied().unwrap_or(false);
            saved_track_response(track, is_favourite)
        })
        .collect();

    Ok(Json(ApiResponse::success(SavedTracksListResponse {
        tracks,
        total_count,
        page,
        limit,
    })))
}

pub async fn remove_saved_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(track_id): Path<Uuid>,
) -> Result<Json<ApiResponse<()>>, StatusCode> {
    let removed = LibrarySyncService::remove_user_track(state.db(), user.id, track_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !removed {
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("Track not found".to_string()),
        }));
    }

    Ok(Json(ApiResponse {
        success: true,
        data: None,
        message: Some("Track removed successfully".to_string()),
    }))
}

pub async fn is_track_saved(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<serde_json::Value>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    let track_id = params
        .get("track_id")
        .and_then(|value| value.as_str())
        .ok_or(StatusCode::BAD_REQUEST)?;
    let source = params
        .get("source")
        .and_then(|value| value.as_str())
        .ok_or(StatusCode::BAD_REQUEST)?;
    let provider = source.parse::<LibraryProvider>().map_err(|_| StatusCode::BAD_REQUEST)?;

    let saved = LibrarySyncService::is_track_saved(state.db(), user.id, provider, track_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(saved)))
}

pub async fn favourite_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<SaveTrackRequest>,
) -> Result<Json<ApiResponse<FavouriteTrackResponse>>, StatusCode> {
    let provider = request
        .source
        .parse::<LibraryProvider>()
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    let (favourite, user_track) = LibrarySyncService::ensure_favourite_track_from_input(
        state.db(),
        user.id,
        provider,
        &request.track_id,
        &request.title,
        &request.artist,
        Some(&request.album),
        Some(request.duration),
        request.cover_url.as_deref(),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(favourite_track_response(favourite, user_track))))
}

pub async fn get_favourite_tracks(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetSavedTracksQuery>,
) -> Result<Json<ApiResponse<FavouriteTracksListResponse>>, StatusCode> {
    let page = params.page.unwrap_or(1);
    let limit = params.limit.unwrap_or(50).min(100);

    let (tracks, total_count) = LibrarySyncService::list_favourite_tracks(
        state.db(),
        user.id,
        params.search.as_deref(),
        page,
        limit,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(FavouriteTracksListResponse {
        tracks: tracks.into_iter().map(favourite_track_summary_response).collect(),
        total_count,
        page,
        limit,
    })))
}

pub async fn remove_favourite_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(user_track_id): Path<Uuid>,
) -> Result<Json<ApiResponse<()>>, StatusCode> {
    let removed = LibrarySyncService::remove_favourite_track(state.db(), user.id, user_track_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !removed {
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("Favourite track not found".to_string()),
        }));
    }

    Ok(Json(ApiResponse {
        success: true,
        data: None,
        message: Some("Favourite removed successfully".to_string()),
    }))
}

pub async fn is_track_favourite(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<serde_json::Value>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    let track_id = params
        .get("track_id")
        .and_then(|value| value.as_str())
        .ok_or(StatusCode::BAD_REQUEST)?;
    let source = params
        .get("source")
        .and_then(|value| value.as_str())
        .ok_or(StatusCode::BAD_REQUEST)?;
    let provider = source.parse::<LibraryProvider>().map_err(|_| StatusCode::BAD_REQUEST)?;

    let favourite = LibrarySyncService::is_track_favourite(state.db(), user.id, provider, track_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(favourite)))
}

pub async fn record_last_played_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<RecordLastPlayedTrackRequest>,
) -> Result<Json<ApiResponse<LastPlayedTrackResponse>>, StatusCode> {
    let track = LibrarySyncService::record_last_played_track(state.db(), user.id, request.user_track_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let summary = LibrarySyncService::list_last_played_tracks(state.db(), user.id, 1)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .into_iter()
        .find(|item| item.id == track.user_track_id)
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(last_played_track_response(summary))))
}

pub async fn get_last_played_tracks(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetLastPlayedTracksQuery>,
) -> Result<Json<ApiResponse<LastPlayedTracksListResponse>>, StatusCode> {
    let limit = params.limit.unwrap_or(20).min(100);
    let tracks = LibrarySyncService::list_last_played_tracks(state.db(), user.id, limit)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(LastPlayedTracksListResponse {
        tracks: tracks.into_iter().map(last_played_track_response).collect(),
        limit,
    })))
}

pub async fn refresh_provider_library(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(provider): Path<String>,
) -> Result<Json<ApiResponse<RefreshProviderResponse>>, StatusCode> {
    let provider = provider.parse::<LibraryProvider>().map_err(|_| StatusCode::BAD_REQUEST)?;
    let summary = LibrarySyncService::refresh_provider_library(state.db(), user.id, provider)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse::success(RefreshProviderResponse {
        provider: summary.provider,
        tracks: summary.tracks,
        albums: summary.albums,
        playlists: summary.playlists,
        canonical_tracks: summary.canonical_tracks,
        canonical_albums: summary.canonical_albums,
        canonical_playlists: summary.canonical_playlists,
        unresolved_tracks: summary.unresolved_tracks,
        unresolved_albums: summary.unresolved_albums,
        unresolved_playlists: summary.unresolved_playlists,
    })))
}

pub async fn get_server_preload_status(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<ServerPreloadProgress>>, StatusCode> {
    let progress = LibrarySyncService::server_preload_status(&state.server_preload_registry, user.id).await;
    Ok(Json(ApiResponse::success(progress)))
}

pub async fn start_server_preload(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<StartServerPreloadRequest>,
) -> Result<Json<ApiResponse<ServerPreloadProgress>>, StatusCode> {
    let mode = request
        .mode
        .parse::<ServerPreloadMode>()
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    let progress = LibrarySyncService::start_server_preload(
        state.db(),
        user.id,
        state.server_preload_registry.clone(),
        mode,
    )
    .await
    .map_err(|error| {
        if error.to_string().contains("already running") {
            StatusCode::CONFLICT
        } else {
            StatusCode::INTERNAL_SERVER_ERROR
        }
    })?;

    Ok(Json(ApiResponse::success(progress)))
}

pub async fn get_unresolved_matches(
    State(state): State<AppState>,
    Extension(_user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<UnresolvedMatchesResponse>>, StatusCode> {
    let unresolved = LibrarySyncService::unresolved_matches(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(ApiResponse::success(unresolved)))
}

fn saved_track_response(track: UserTrackModel, is_favourite: bool) -> SavedTrackResponse {
    SavedTrackResponse {
        id: track.id,
        canonical_track_id: track.canonical_track_id,
        track_id: track.provider_track_id,
        title: track.title,
        artist: track.artist,
        album: track.album_name.unwrap_or_default(),
        duration: track.duration,
        source: track.source,
        cover_url: cache_cover_url(track.cover_url),
        is_favourite,
        created_at: track.created_at,
        updated_at: track.updated_at,
    }
}

fn favourite_track_response(
    favourite: crate::models::FavouriteTrackModel,
    user_track: UserTrackModel,
) -> FavouriteTrackResponse {
    FavouriteTrackResponse {
        id: favourite.id,
        user_track_id: favourite.user_track_id,
        canonical_track_id: user_track.canonical_track_id,
        track_id: favourite.provider_track_id,
        title: favourite.title,
        artist: favourite.artist,
        album: favourite.album_name.unwrap_or_default(),
        duration: favourite.duration,
        source: favourite.source,
        cover_url: cache_cover_url(favourite.cover_url),
        created_at: favourite.created_at,
        updated_at: favourite.updated_at,
    }
}

fn favourite_track_summary_response(track: crate::services::FavouriteTrackSummary) -> FavouriteTrackResponse {
    FavouriteTrackResponse {
        id: track.id,
        user_track_id: track.user_track_id,
        canonical_track_id: track.canonical_track_id,
        track_id: track.provider_track_id,
        title: track.title,
        artist: track.artist,
        album: track.album_name.unwrap_or_default(),
        duration: track.duration,
        source: track.source,
        cover_url: cache_cover_url(track.cover_url),
        created_at: track.created_at,
        updated_at: track.updated_at,
    }
}

fn last_played_track_response(track: crate::services::LastPlayedTrackSummary) -> LastPlayedTrackResponse {
    LastPlayedTrackResponse {
        id: track.id,
        canonical_track_id: track.canonical_track_id,
        track_id: track.provider_track_id,
        title: track.title,
        artist: track.artist,
        album: track.album_name.unwrap_or_default(),
        duration: track.duration,
        source: track.source,
        cover_url: cache_cover_url(track.cover_url),
        played_at: track.played_at,
        created_at: track.created_at,
        updated_at: track.updated_at,
    }
}
