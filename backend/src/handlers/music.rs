use axum::{
    extract::{State, Query, Extension, Path},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use uuid::{Uuid, Timestamp};

use crate::models::{UserResponseDto, CreatePlaylistDto, PlaylistResponseDto};
use crate::handlers::auth::{AppState, ApiResponse};

#[derive(Deserialize)]
pub struct GetPlaylistsQuery {
    pub limit: Option<u64>,
    pub offset: Option<u64>,
}

// For MVP, we'll implement basic playlist functionality
pub async fn get_user_playlists(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetPlaylistsQuery>,
) -> Result<Json<ApiResponse<Vec<PlaylistResponseDto>>>, (StatusCode, Json<ApiResponse<()>>)> {
    // For MVP, return empty list
    // In full implementation, this would query the database
    Ok(Json(ApiResponse::success(vec![])))
}

pub async fn create_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(playlist_data): Json<CreatePlaylistDto>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, (StatusCode, Json<ApiResponse<()>>)> {
    // For MVP, return a mock response
    // In full implementation, this would create in database
    let mock_playlist = PlaylistResponseDto {
        id: Uuid::new_v7(Timestamp::now(uuid::NoContext)),
        name: playlist_data.name,
        description: playlist_data.description,
        is_public: playlist_data.is_public.unwrap_or(false),
        created_at: chrono::Utc::now().naive_utc(),
        updated_at: chrono::Utc::now().naive_utc(),
    };
    
    Ok(Json(ApiResponse::success(mock_playlist)))
}

pub async fn get_playlist(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PlaylistResponseDto>>, (StatusCode, Json<ApiResponse<()>>)> {
    // For MVP, return not found
    Err((
        StatusCode::NOT_FOUND,
        Json(ApiResponse::<()>::error("Playlist not found".to_string())),
    ))
}
