use axum::{
    extract::{State, Query, Extension},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::services::streaming::{QobuzService, SpotifyService, StreamingService, SearchResults};
use crate::models::{UserResponseDto, SearchQuery};
use crate::handlers::auth::{AppState, ApiResponse};

#[derive(Deserialize)]
pub struct StreamingSearchQuery {
    pub q: String,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
    pub service: Option<String>,
}

#[derive(Deserialize)]
pub struct GetStreamUrlQuery {
    pub track_id: String,
    pub quality: Option<String>,
    pub service: Option<String>,
}

fn get_streaming_service(service_name: &str) -> Result<Box<dyn StreamingService>, String> {
    match service_name {
        "qobuz" => {
            let service = QobuzService::new(
                std::env::var("QOBUZ_APP_ID").unwrap_or_default(),
                std::env::var("QOBUZ_SECRET").unwrap_or_default(),
            );
            Ok(Box::new(service))
        },
        "spotify" => {
            let service = SpotifyService::new(
                std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default(),
                std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default(),
            );
            Ok(Box::new(service))
        },
        _ => Err(format!("Unsupported streaming service: {}", service_name)),
    }
}

pub async fn search_music(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<StreamingSearchQuery>,
) -> Result<Json<ApiResponse<SearchResults>>, (StatusCode, Json<ApiResponse<()>>)> {
    let service_name = params.service.as_deref().unwrap_or("qobuz");
    
    let service = match get_streaming_service(service_name) {
        Ok(service) => service,
        Err(err) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()>::error(err)),
            ));
        }
    };

    match service.search(&params.q, params.limit, params.offset).await {
        Ok(results) => Ok(Json(ApiResponse::success(results))),
        Err(err) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Search failed: {}", err))),
        )),
    }
}

pub async fn get_stream_url(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetStreamUrlQuery>,
) -> Result<Json<ApiResponse<String>>, (StatusCode, Json<ApiResponse<()>>)> {
    let service_name = params.service.as_deref().unwrap_or("qobuz");
    
    let service = match get_streaming_service(service_name) {
        Ok(service) => service,
        Err(err) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()>::error(err)),
            ));
        }
    };

    match service.get_stream_url(&params.track_id, params.quality.as_deref()).await {
        Ok(stream_url) => Ok(Json(ApiResponse::success(stream_url))),
        Err(err) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Failed to get stream URL: {}", err))),
        )),
    }
}

#[derive(Deserialize)]
pub struct ConnectQobuzRequest {
    pub username: String,
    pub password: String,
}

#[derive(Deserialize)]
pub struct ConnectSpotifyRequest {
    pub access_token: String,
    pub refresh_token: Option<String>,
}

#[derive(Serialize)]
pub struct AvailableServicesResponse {
    pub services: Vec<ServiceInfo>,
}

#[derive(Serialize)]
pub struct ServiceInfo {
    pub name: String,
    pub display_name: String,
    pub supports_full_tracks: bool,
    pub requires_premium: bool,
}

pub async fn connect_qobuz(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<ConnectQobuzRequest>,
) -> Result<Json<ApiResponse<String>>, (StatusCode, Json<ApiResponse<()>>)> {
    let qobuz_service = QobuzService::new(
        std::env::var("QOBUZ_APP_ID").unwrap_or_default(),
        std::env::var("QOBUZ_SECRET").unwrap_or_default(),
    );

    let credentials = crate::services::streaming::ServiceCredentials {
        username: Some(request.username),
        password: Some(request.password),
        access_token: None,
        refresh_token: None,
        app_id: Some(std::env::var("QOBUZ_APP_ID").unwrap_or_default()),
        secret: Some(std::env::var("QOBUZ_SECRET").unwrap_or_default()),
    };

    match qobuz_service.authenticate(&credentials).await {
        Ok(auth_result) => {
            // In a real implementation, you'd store this in the database
            // For MVP, we'll just return the auth token
            if let Some(token) = auth_result.access_token {
                Ok(Json(ApiResponse::success(token)))
            } else {
                Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error("Authentication succeeded but no token received".to_string())),
                ))
            }
        },
        Err(err) => Err((
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error(format!("Qobuz authentication failed: {}", err))),
        )),
    }
}

pub async fn connect_spotify(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<ConnectSpotifyRequest>,
) -> Result<Json<ApiResponse<String>>, (StatusCode, Json<ApiResponse<()>>)> {
    let spotify_service = SpotifyService::new(
        std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default(),
        std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default(),
    ).with_tokens(request.access_token.clone(), request.refresh_token.clone());

    let credentials = crate::services::streaming::ServiceCredentials {
        username: None,
        password: None,
        access_token: Some(request.access_token),
        refresh_token: request.refresh_token,
        app_id: Some(std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default()),
        secret: Some(std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default()),
    };

    match spotify_service.authenticate(&credentials).await {
        Ok(auth_result) => {
            // In a real implementation, you'd store this in the database
            // For MVP, we'll just return success
            Ok(Json(ApiResponse::success("Spotify connected successfully".to_string())))
        },
        Err(err) => Err((
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error(format!("Spotify authentication failed: {}", err))),
        )),
    }
}

pub async fn get_available_services(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Json<ApiResponse<AvailableServicesResponse>> {
    let services = vec![
        ServiceInfo {
            name: "qobuz".to_string(),
            display_name: "Qobuz".to_string(),
            supports_full_tracks: true,
            requires_premium: true,
        },
        ServiceInfo {
            name: "spotify".to_string(),
            display_name: "Spotify".to_string(),
            supports_full_tracks: false, // Only 30-second previews via Web API
            requires_premium: false,
        },
    ];

    Json(ApiResponse::success(AvailableServicesResponse { services }))
}
