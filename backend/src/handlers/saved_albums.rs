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
    models::{SavedAlbumEntity, UserResponseDto, StreamingServiceEntity, StreamingServiceColumn},
    services::streaming::{StreamingTrack, QobuzService, SpotifyService, LocalMusicService, StreamingService},
};

#[derive(Deserialize, Debug)]
pub struct SaveAlbumRequest {
    pub album_id: String,
    pub title: String,
    pub artist: String,
    pub release_date: Option<String>,
    pub cover_url: Option<String>,
    pub source: String,
    pub track_count: i32,
}

#[derive(Serialize)]
pub struct SavedAlbumResponse {
    pub id: Uuid,
    pub album_id: String,
    pub title: String,
    pub artist: String,
    pub release_date: Option<String>,
    pub cover_url: Option<String>,
    pub source: String,
    pub track_count: i32,
    pub created_at: chrono::NaiveDateTime,
}

#[derive(Deserialize)]
pub struct GetSavedAlbumsQuery {
    pub page: Option<u64>,
    pub limit: Option<u64>,
}

#[derive(Deserialize)]
pub struct CheckAlbumSavedQuery {
    pub album_id: String,
    pub source: String,
}

#[derive(Deserialize)]
pub struct GetAlbumTracksQuery {
    pub source: String,
}

async fn get_authenticated_streaming_service(
    service_name: &str, 
    user_id: uuid::Uuid, 
    db: &sea_orm::DatabaseConnection
) -> Result<Box<dyn StreamingService>, String> {
    match service_name {
        "qobuz" => {
            let app_id = std::env::var("QOBUZ_APP_ID").unwrap_or_default();
            let secret = std::env::var("QOBUZ_SECRET").unwrap_or_default();
            
            if app_id.is_empty() || secret.is_empty() {
                return Err("Qobuz credentials not configured".to_string());
            }
            
            // Look up stored user credentials
            let user_service = StreamingServiceEntity::find()
                .filter(StreamingServiceColumn::UserId.eq(user_id))
                .filter(StreamingServiceColumn::ServiceName.eq("qobuz"))
                .filter(StreamingServiceColumn::IsActive.eq(true))
                .one(db)
                .await
                .map_err(|e| format!("Database error: {}", e))?;
                
            if let Some(service) = user_service {
                if let Some(token) = service.access_token {
                    Ok(Box::new(QobuzService::new(app_id, secret).with_auth_token(token)))
                } else {
                    Err("No access token found for Qobuz service".to_string())
                }
            } else {
                Err("Qobuz service not connected for this user. Please connect to Qobuz first.".to_string())
            }
        },
        "spotify" => {
            let client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
            let client_secret = std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default();
            
            if client_id.is_empty() || client_secret.is_empty() {
                return Err("Spotify credentials not configured".to_string());
            }
            
            // Look up stored user credentials
            let user_service = StreamingServiceEntity::find()
                .filter(StreamingServiceColumn::UserId.eq(user_id))
                .filter(StreamingServiceColumn::ServiceName.eq("spotify"))
                .filter(StreamingServiceColumn::IsActive.eq(true))
                .one(db)
                .await
                .map_err(|e| format!("Database error: {}", e))?;
                
            if let Some(service) = user_service {
                if let (Some(access_token), refresh_token) = (service.access_token, service.refresh_token) {
                    Ok(Box::new(SpotifyService::new(client_id, client_secret)
                        .with_tokens(access_token, refresh_token)))
                } else {
                    Err("No access token found for Spotify service".to_string())
                }
            } else {
                Err("Spotify service not connected for this user. Please connect to Spotify first.".to_string())
            }
        },
        "server" => {
            // Server service doesn't require authentication, just return the service
            let music_dir = std::env::current_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from("."))
                .join("own_music");
            let service = LocalMusicService::new(music_dir);
            Ok(Box::new(service))
        },
        _ => Err(format!("Unknown streaming service: {}", service_name)),
    }
}

pub async fn save_album(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<SaveAlbumRequest>,
) -> Result<Json<ApiResponse<SavedAlbumResponse>>, StatusCode> {
    debug!("save_album called with request: {:?}", request);
    debug!("User ID: {:?}", user.id);
    
    // Check if album already exists for this user and source
    debug!("Starting duplicate check query...");
    let existing_album = SavedAlbumEntity::find()
        .filter(crate::models::SavedAlbumColumn::UserId.eq(user.id))
        .filter(crate::models::SavedAlbumColumn::AlbumId.eq(&request.album_id))
        .filter(crate::models::SavedAlbumColumn::Source.eq(&request.source))
        .one(state.db())
        .await
        .map_err(|e| {
            error!("Error during duplicate check query: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    debug!("Duplicate check completed, existing_album: {:?}", existing_album.is_some());

    if existing_album.is_some() {
        debug!("Album already exists, returning early");
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("Album already saved".to_string()),
        }));
    }

    debug!("Album does not exist, proceeding to create new saved album");
    // Create new saved album
    debug!("Creating SavedAlbumActiveModel...");
    let saved_album = crate::models::SavedAlbumActiveModel {
        id: Set(Uuid::new_v4()),
        user_id: Set(user.id),
        album_id: Set(request.album_id.clone()),
        title: Set(request.title.clone()),
        artist: Set(request.artist.clone()),
        release_date: Set(request.release_date.clone()),
        cover_url: Set(request.cover_url.clone()),
        source: Set(request.source.clone()),
        track_count: Set(request.track_count),
        created_at: Set(chrono::Utc::now().naive_utc()),
    };
    debug!("SavedAlbumActiveModel created successfully");
    debug!("Attempting to insert into database...");

    let saved_album_model = saved_album.insert(state.db()).await.map_err(|e| {
        error!("Error inserting saved album: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    debug!("Successfully inserted saved album with ID: {:?}", saved_album_model.id);

    let response = SavedAlbumResponse {
        id: saved_album_model.id,
        album_id: saved_album_model.album_id,
        title: saved_album_model.title,
        artist: saved_album_model.artist,
        release_date: saved_album_model.release_date,
        cover_url: saved_album_model.cover_url,
        source: saved_album_model.source,
        track_count: saved_album_model.track_count,
        created_at: saved_album_model.created_at,
    };

    Ok(Json(ApiResponse {
        success: true,
        data: Some(response),
        message: Some("Album saved successfully".to_string()),
    }))
}

pub async fn get_saved_albums(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetSavedAlbumsQuery>,
) -> Result<Json<ApiResponse<Vec<SavedAlbumResponse>>>, StatusCode> {
    debug!("get_saved_albums called for user: {:?}", user.id);

    let page = params.page.unwrap_or(1);
    let limit = params.limit.unwrap_or(50);
    let offset = (page - 1) * limit;

    let saved_albums = SavedAlbumEntity::find()
        .filter(crate::models::SavedAlbumColumn::UserId.eq(user.id))
        .order_by_desc(crate::models::SavedAlbumColumn::CreatedAt)
        .limit(limit)
        .offset(offset)
        .all(state.db())
        .await
        .map_err(|e| {
            error!("Error fetching saved albums: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let response: Vec<SavedAlbumResponse> = saved_albums
        .into_iter()
        .map(|album| SavedAlbumResponse {
            id: album.id,
            album_id: album.album_id,
            title: album.title,
            artist: album.artist,
            release_date: album.release_date,
            cover_url: album.cover_url,
            source: album.source,
            track_count: album.track_count,
            created_at: album.created_at,
        })
        .collect();

    debug!("Found {} saved albums", response.len());

    Ok(Json(ApiResponse {
        success: true,
        data: Some(response),
        message: None,
    }))
}

pub async fn remove_saved_album(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(album_id): Path<String>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    debug!("remove_saved_album called for album_id: {:?}, user: {:?}", album_id, user.id);

    let album_uuid = Uuid::parse_str(&album_id).map_err(|_| StatusCode::BAD_REQUEST)?;

    // Find and delete the album
    let delete_result = SavedAlbumEntity::delete_by_id(album_uuid)
        .filter(crate::models::SavedAlbumColumn::UserId.eq(user.id))
        .exec(state.db())
        .await
        .map_err(|e| {
            error!("Error deleting saved album: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if delete_result.rows_affected == 0 {
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("Album not found or not owned by user".to_string()),
        }));
    }

    debug!("Successfully deleted saved album");

    Ok(Json(ApiResponse {
        success: true,
        data: Some("Album removed successfully".to_string()),
        message: None,
    }))
}

pub async fn check_album_saved(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<CheckAlbumSavedQuery>,
) -> Result<Json<ApiResponse<bool>>, StatusCode> {
    debug!("check_album_saved called for album_id: {:?}, source: {:?}, user: {:?}", 
           params.album_id, params.source, user.id);

    let exists = SavedAlbumEntity::find()
        .filter(crate::models::SavedAlbumColumn::UserId.eq(user.id))
        .filter(crate::models::SavedAlbumColumn::AlbumId.eq(&params.album_id))
        .filter(crate::models::SavedAlbumColumn::Source.eq(&params.source))
        .one(state.db())
        .await
        .map_err(|e| {
            error!("Error checking if album is saved: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .is_some();

    Ok(Json(ApiResponse {
        success: true,
        data: Some(exists),
        message: None,
    }))
}

pub async fn get_album_tracks(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(album_id): Path<String>,
    Query(params): Query<GetAlbumTracksQuery>,
) -> Result<Json<ApiResponse<Vec<StreamingTrack>>>, StatusCode> {
    debug!("get_album_tracks called for album_id: {:?}, source: {:?}", album_id, params.source);

    // Get the streaming service
    let service = match get_authenticated_streaming_service(&params.source, user.id, state.db()).await {
        Ok(service) => service,
        Err(err) => {
            error!("Failed to get streaming service: {}", err);
            return Err(StatusCode::BAD_REQUEST);
        }
    };

    // Get album tracks from the streaming service
    match service.get_album_tracks(&album_id).await {
        Ok(tracks) => {
            debug!("Found {} tracks for album {}", tracks.len(), album_id);
            Ok(Json(ApiResponse {
                success: true,
                data: Some(tracks),
                message: None,
            }))
        },
        Err(err) => {
            error!("Error fetching album tracks: {}", err);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}
