use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::Json,
    Extension,
};
use sea_orm::{EntityTrait, ColumnTrait, ActiveModelTrait, QueryFilter, QueryOrder, QuerySelect, Set};
use serde::{Deserialize, Serialize};
use tracing::{debug, error};
use uuid::Uuid;

use crate::{
    handlers::auth::{AppState, ApiResponse},
    models::{SavedTrackEntity, UserResponseDto},
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
    pub track_id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: i32,
    pub source: String,
    pub cover_url: Option<String>,
    pub bpm: Option<f32>,
    pub created_at: chrono::NaiveDateTime,
}

#[derive(Deserialize)]
pub struct GetSavedTracksQuery {
    pub page: Option<u64>,
    pub limit: Option<u64>,
}

pub async fn save_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<SaveTrackRequest>,
) -> Result<Json<ApiResponse<SavedTrackResponse>>, StatusCode> {
    debug!("save_track called with request: {:?}", request);
    debug!("User ID: {:?}", user.id);
    
    // Check if track already exists for this user and source
    debug!("Starting duplicate check query...");
    let existing_track = SavedTrackEntity::find()
        .filter(crate::models::SavedTrackColumn::UserId.eq(user.id))
        .filter(crate::models::SavedTrackColumn::TrackId.eq(&request.track_id))
        .filter(crate::models::SavedTrackColumn::Source.eq(&request.source))
        .one(state.db())
        .await
        .map_err(|e| {
            error!("Error during duplicate check query: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    debug!("Duplicate check completed, existing_track: {:?}", existing_track.is_some());

    if existing_track.is_some() {
        debug!("Track already exists, returning early");
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("Track already saved".to_string()),
        }));
    }

    debug!("Track does not exist, proceeding to create new saved track");
    // Create new saved track
    debug!("Creating SavedTrackActiveModel...");
    let saved_track = crate::models::SavedTrackActiveModel {
        id: Set(Uuid::new_v4()),
        user_id: Set(user.id),
        track_id: Set(request.track_id.clone()),
        title: Set(request.title.clone()),
        artist: Set(request.artist.clone()),
        album: Set(request.album.clone()),
        duration: Set(request.duration),
        source: Set(request.source.clone()),
        cover_url: Set(request.cover_url.clone()),
        bpm: Set(None), // BPM not available when saving track initially
        key_name: Set(None), // Key not available when saving track initially
        camelot: Set(None), // Camelot not available when saving track initially
        key_confidence: Set(None), // Key confidence not available when saving track initially
        created_at: Set(chrono::Utc::now().naive_utc()),
    };
    debug!("SavedTrackActiveModel created successfully");
    debug!("Attempting to insert into database...");

    let result = saved_track.insert(state.db()).await.map_err(|e| {
        error!("Error inserting saved track: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    debug!("Successfully inserted saved track with ID: {:?}", result.id);

    let response = SavedTrackResponse {
        id: result.id,
        track_id: result.track_id,
        title: result.title,
        artist: result.artist,
        album: result.album,
        duration: result.duration,
        source: result.source,
        cover_url: result.cover_url,
        bpm: result.bpm,
        created_at: result.created_at,
    };

    Ok(Json(ApiResponse {
        success: true,
        data: Some(response),
        message: Some("Track saved successfully".to_string()),
    }))
}

pub async fn get_saved_tracks(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetSavedTracksQuery>,
) -> Result<Json<ApiResponse<Vec<SavedTrackResponse>>>, StatusCode> {
    let page = params.page.unwrap_or(1);
    let limit = params.limit.unwrap_or(50).min(100); // Max 100 per page
    let offset = (page - 1) * limit;

    let saved_tracks = SavedTrackEntity::find()
        .filter(crate::models::SavedTrackColumn::UserId.eq(user.id))
        .order_by_desc(crate::models::SavedTrackColumn::CreatedAt)
        .offset(offset)
        .limit(limit)
        .all(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let response: Vec<SavedTrackResponse> = saved_tracks
        .into_iter()
        .map(|track| SavedTrackResponse {
            id: track.id,
            track_id: track.track_id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            source: track.source,
            cover_url: track.cover_url,
            bpm: track.bpm,
            created_at: track.created_at,
        })
        .collect();

    Ok(Json(ApiResponse {
        success: true,
        data: Some(response),
        message: Some("Saved tracks retrieved successfully".to_string()),
    }))
}

pub async fn remove_saved_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(track_id): Path<Uuid>,
) -> Result<Json<ApiResponse<()>>, StatusCode> {
    let result = SavedTrackEntity::delete_many()
        .filter(crate::models::SavedTrackColumn::Id.eq(track_id))
        .filter(crate::models::SavedTrackColumn::UserId.eq(user.id))
        .exec(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if result.rows_affected == 0 {
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
    let track_id = params.get("track_id")
        .and_then(|v| v.as_str())
        .ok_or(StatusCode::BAD_REQUEST)?;
    let source = params.get("source")
        .and_then(|v| v.as_str())
        .ok_or(StatusCode::BAD_REQUEST)?;

    let saved_track = SavedTrackEntity::find()
        .filter(crate::models::SavedTrackColumn::UserId.eq(user.id))
        .filter(crate::models::SavedTrackColumn::TrackId.eq(track_id))
        .filter(crate::models::SavedTrackColumn::Source.eq(source))
        .one(state.db())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(ApiResponse {
        success: true,
        data: Some(saved_track.is_some()),
        message: Some("Track saved status retrieved".to_string()),
    }))
}
