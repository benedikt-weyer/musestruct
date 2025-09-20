use axum::{
    extract::{State, Query, Extension},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use sea_orm::{EntityTrait, Set, ActiveModelTrait, ColumnTrait, QueryFilter};

use crate::services::streaming::{QobuzService, SpotifyService, StreamingService, SearchResults};
use crate::models::{UserResponseDto, SearchQuery, StreamingServiceEntity, StreamingServiceActiveModel, StreamingServiceColumn}; 
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
                if let Some(token) = service.access_token {
                    Ok(Box::new(SpotifyService::new(client_id, client_secret).with_tokens(token, service.refresh_token)))
                } else {
                    Err("No access token found for Spotify service".to_string())
                }
            } else {
                Err("Spotify service not connected for this user. Please connect to Spotify first.".to_string())
            }
        },
        _ => Err(format!("Unknown streaming service: {}", service_name)),
    }
}

pub async fn search_music(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<StreamingSearchQuery>,
) -> Result<Json<ApiResponse<SearchResults>>, (StatusCode, Json<ApiResponse<()>>)> {
    let service_name = params.service.as_deref().unwrap_or("qobuz");
    
    let service = match get_authenticated_streaming_service(service_name, user.id, state.db()).await {
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
    
    let service = match get_authenticated_streaming_service(service_name, user.id, state.db()).await {
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

    let username = request.username.clone();
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
            if let Some(token) = auth_result.access_token {
                // Get the username from the authentication result
                let account_username = auth_result.user_id.map(|_| username);
                
                // Save the authentication to the database
                // First, check if user already has a Qobuz service entry
                let existing_service = StreamingServiceEntity::find()
                    .filter(StreamingServiceColumn::UserId.eq(user.id))
                    .filter(StreamingServiceColumn::ServiceName.eq("qobuz"))
                    .one(state.db())
                    .await;

                match existing_service {
                    Ok(Some(existing)) => {
                        // Update existing service
                        let mut service: StreamingServiceActiveModel = existing.into();
                        service.access_token = Set(Some(token.clone()));
                        service.account_username = Set(account_username);
                        service.is_active = Set(true);
                        
                        if let Err(e) = service.update(state.db()).await {
                            return Err((
                                StatusCode::INTERNAL_SERVER_ERROR,
                                Json(ApiResponse::<()>::error(format!("Failed to update Qobuz connection: {}", e))),
                            ));
                        }
                    },
                    Ok(None) => {
                        // Create new service entry
                        let new_service = StreamingServiceActiveModel {
                            user_id: Set(user.id),
                            service_name: Set("qobuz".to_string()),
                            access_token: Set(Some(token.clone())),
                            refresh_token: Set(None),
                            expires_at: Set(None), // Qobuz tokens don't expire
                            account_username: Set(account_username),
                            is_active: Set(true),
                            ..Default::default()
                        };
                        
                        if let Err(e) = new_service.insert(state.db()).await {
                            return Err((
                                StatusCode::INTERNAL_SERVER_ERROR,
                                Json(ApiResponse::<()>::error(format!("Failed to save Qobuz connection: {}", e))),
                            ));
                        }
                    },
                    Err(e) => {
                        return Err((
                            StatusCode::INTERNAL_SERVER_ERROR,
                            Json(ApiResponse::<()>::error(format!("Database error: {}", e))),
                        ));
                    }
                }

                Ok(Json(ApiResponse::success("Successfully connected to Qobuz".to_string())))
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

#[derive(Serialize)]
pub struct ServiceStatusResponse {
    pub services: Vec<ConnectedServiceInfo>,
}

#[derive(Serialize)]
pub struct ConnectedServiceInfo {
    pub name: String,
    pub display_name: String,
    pub is_connected: bool,
    pub connected_at: Option<String>,
    pub account_username: Option<String>,
}

pub async fn get_service_status(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<ServiceStatusResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    // Check Qobuz connection
    let qobuz_connected = match get_authenticated_streaming_service("qobuz", user.id, state.db()).await {
        Ok(_) => true,
        Err(_) => false,
    };

    // Check Spotify connection
    let spotify_connected = match get_authenticated_streaming_service("spotify", user.id, state.db()).await {
        Ok(_) => true,
        Err(_) => false,
    };

    // Get connection timestamps from database
    let qobuz_service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user.id))
        .filter(StreamingServiceColumn::ServiceName.eq("qobuz"))
        .filter(StreamingServiceColumn::IsActive.eq(true))
        .one(state.db())
        .await
        .map_err(|e| (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Database error: {}", e)))
        ))?;

    let spotify_service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user.id))
        .filter(StreamingServiceColumn::ServiceName.eq("spotify"))
        .filter(StreamingServiceColumn::IsActive.eq(true))
        .one(state.db())
        .await
        .map_err(|e| (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Database error: {}", e)))
        ))?;

    let services = vec![
        ConnectedServiceInfo {
            name: "qobuz".to_string(),
            display_name: "Qobuz".to_string(),
            is_connected: qobuz_connected,
            connected_at: qobuz_service.as_ref().map(|s| s.created_at.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()),
            account_username: qobuz_service.as_ref().and_then(|s| s.account_username.clone()),
        },
        ConnectedServiceInfo {
            name: "spotify".to_string(),
            display_name: "Spotify".to_string(),
            is_connected: spotify_connected,
            connected_at: spotify_service.as_ref().map(|s| s.created_at.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()),
            account_username: spotify_service.as_ref().and_then(|s| s.account_username.clone()),
        },
    ];

    Ok(Json(ApiResponse::success(ServiceStatusResponse { services })))
}

#[derive(Deserialize)]
pub struct DisconnectServiceRequest {
    pub service_name: String,
}

pub async fn disconnect_service(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<DisconnectServiceRequest>,
) -> Result<Json<ApiResponse<String>>, (StatusCode, Json<ApiResponse<()>>)> {
    let service_name = &request.service_name;
    
    // Validate service name
    if service_name != "qobuz" && service_name != "spotify" {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ApiResponse::<()>::error("Invalid service name".to_string())),
        ));
    }

    // Find and deactivate the service
    let service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user.id))
        .filter(StreamingServiceColumn::ServiceName.eq(service_name))
        .filter(StreamingServiceColumn::IsActive.eq(true))
        .one(state.db())
        .await
        .map_err(|e| (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Database error: {}", e)))
        ))?;

    match service {
        Some(service) => {
            let mut service: StreamingServiceActiveModel = service.into();
            service.is_active = Set(false);
            service.access_token = Set(None);
            service.refresh_token = Set(None);
            
            service.update(state.db()).await
                .map_err(|e| (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!("Failed to disconnect service: {}", e)))
                ))?;

            Ok(Json(ApiResponse::success(format!("Successfully disconnected from {}", service_name))))
        },
        None => Err((
            StatusCode::NOT_FOUND,
            Json(ApiResponse::<()>::error(format!("{} service not connected", service_name))),
        )),
    }
}
