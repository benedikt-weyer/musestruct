use axum::{
    extract::{State, Query, Extension, Path},
    http::{StatusCode, HeaderMap, header},
    response::{Json, Html, Response},
};
use tracing::{debug, error};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use sea_orm::{EntityTrait, Set, ActiveModelTrait, ColumnTrait, QueryFilter};

use crate::services::streaming::{QobuzService, SpotifyService, LocalMusicService, StreamingService, SearchResults, StreamingTrack};
use crate::services::streaming_service::StreamingService as BackendStreamingService;
use crate::models::{UserResponseDto, SearchQuery, StreamingServiceEntity, StreamingServiceActiveModel, StreamingServiceColumn}; 
use crate::handlers::auth::{AppState, ApiResponse};
use std::sync::Arc;

#[derive(Deserialize)]
pub struct StreamingSearchQuery {
    pub q: String,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
    pub service: Option<String>,
    pub services: Option<Vec<String>>, // For multi-service search
    pub r#type: Option<String>, // "track" or "playlist"
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
        "server" => {
            // Create own_music directory path
            let music_dir = std::env::current_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from("."))
                .join("own_music");
            let service = LocalMusicService::new(music_dir);
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

pub async fn search_music(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<StreamingSearchQuery>,
) -> Result<Json<ApiResponse<SearchResults>>, (StatusCode, Json<ApiResponse<()>>)> {
    // Determine which services to search
    let services_to_search = if let Some(services) = &params.services {
        if services.is_empty() {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()>::error("No services specified for search".to_string())),
            ));
        }
        services.clone()
    } else if let Some(service) = &params.service {
        vec![service.clone()]
    } else {
        vec!["qobuz".to_string()] // Default to qobuz
    };

    let mut all_tracks = Vec::new();
    let mut all_albums = Vec::new();
    let mut all_playlists = Vec::new();
    let mut total_results = 0;
    let mut search_errors = Vec::new();

    // Determine search type
    let search_type = params.r#type.as_deref().unwrap_or("track");
    println!("Backend: Search type: {}", search_type);
    println!("Backend: Services to search: {:?}", services_to_search);

    // Search each service
    for service_name in &services_to_search {
        match get_authenticated_streaming_service(service_name, user.id, state.db()).await {
            Ok(service) => {
                if search_type == "playlist" {
                    // Search for playlists
                    println!("Backend: Searching playlists on {} for query: {}", service_name, params.q);
                    match service.search_playlists(&params.q, params.limit, params.offset).await {
                        Ok(playlists) => {
                            let playlist_count = playlists.len() as u32;
                            println!("Backend: Found {} playlists on {}", playlist_count, service_name);
                            all_playlists.extend(playlists);
                            total_results += playlist_count;
                        },
                        Err(err) => {
                            println!("Backend: Error searching playlists on {}: {}", service_name, err);
                            search_errors.push(format!("{}: {}", service_name, err));
                        }
                    }
                } else {
                    // Search for tracks and albums
                    match service.search(&params.q, params.limit, params.offset).await {
                        Ok(results) => {
                            all_tracks.extend(results.tracks);
                            all_albums.extend(results.albums);
                            all_playlists.extend(results.playlists);
                            total_results += results.total;
                        },
                        Err(err) => {
                            search_errors.push(format!("{}: {}", service_name, err));
                        }
                    }
                }
            },
            Err(err) => {
                search_errors.push(format!("{}: {}", service_name, err));
            }
        }
    }

    // If all services failed, return an error
    if all_tracks.is_empty() && all_albums.is_empty() && all_playlists.is_empty() && !search_errors.is_empty() {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Search failed on all services: {}", search_errors.join(", ")))),
        ));
    }

    // Sort tracks by relevance (you could implement more sophisticated sorting)
    all_tracks.sort_by(|a, b| a.title.cmp(&b.title));
    
    // Limit results if needed
    let limit = params.limit.unwrap_or(20) as usize;
    if all_tracks.len() > limit {
        all_tracks.truncate(limit);
    }
    if all_playlists.len() > limit {
        all_playlists.truncate(limit);
    }

    let combined_results = SearchResults {
        tracks: all_tracks,
        albums: all_albums,
        playlists: all_playlists,
        total: total_results,
        offset: params.offset.unwrap_or(0),
        limit: params.limit.unwrap_or(20),
    };

    Ok(Json(ApiResponse::success(combined_results)))
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
pub struct SpotifyAuthUrlResponse {
    pub auth_url: String,
    pub state: String,
}

#[derive(Deserialize)]
pub struct SpotifyCallbackQuery {
    pub code: Option<String>,
    pub state: Option<String>,
    pub error: Option<String>,
}

#[derive(Deserialize)]
pub struct SpotifyTokenRequest {
    pub code: String,
    pub state: String,
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

pub async fn get_spotify_auth_url(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<SpotifyAuthUrlResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
    let redirect_uri = std::env::var("SPOTIFY_REDIRECT_URI").unwrap_or_else(|_| "http://127.0.0.1:8080/api/streaming/spotify/callback".to_string());
    
    if client_id.is_empty() {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error("Spotify client ID not configured".to_string())),
        ));
    }

    // Generate a random state parameter for security and include user ID
    let state_uuid = uuid::Uuid::new_v4();
    let state = format!("{}:{}", state_uuid, user.id);
    
    // Store the state with user ID in the database for validation
    // For now, we'll include it in the response and validate it in the callback
    
    let scopes = vec![
        "user-read-private",
        "user-read-email",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "streaming",
        "user-read-recently-played",
        "user-top-read",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-library-modify"
    ].join(" ");

    let auth_url = format!(
        "https://accounts.spotify.com/authorize?response_type=code&client_id={}&scope={}&redirect_uri={}&state={}",
        client_id,
        urlencoding::encode(&scopes),
        urlencoding::encode(&redirect_uri),
        state
    );

    Ok(Json(ApiResponse::success(SpotifyAuthUrlResponse {
        auth_url,
        state,
    })))
}

pub async fn spotify_callback(
    State(state): State<AppState>,
    Query(params): Query<SpotifyCallbackQuery>,
) -> Result<Html<String>, (StatusCode, Html<String>)> {
    if let Some(error) = params.error {
        let error_html = format!(r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Authorization Error - Musestruct</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }}
        .container {{
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }}
        .error-icon {{
            width: 80px;
            height: 80px;
            background: #ff6b6b;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-size: 40px;
            color: white;
        }}
        h1 {{
            color: #ff6b6b;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }}
        p {{
            color: #666;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }}
        .close-btn {{
            background: #ff6b6b;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="error-icon">✗</div>
        <h1>❌ Authorization Failed</h1>
        <p>Spotify authorization was denied or failed: {}</p>
        <button class="close-btn" onclick="window.close()">Close Window</button>
    </div>
</body>
</html>
        "#, error);
        return Err((StatusCode::BAD_REQUEST, Html(error_html)));
    }

    let code = match params.code {
        Some(code) => code,
        None => {
            let error_html = r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Connection Error - Musestruct</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }
        .error-icon {
            width: 80px;
            height: 80px;
            background: #ff6b6b;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-size: 40px;
            color: white;
        }
        h1 {
            color: #ff6b6b;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }
        p {
            color: #666;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }
        .close-btn {
            background: #ff6b6b;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-icon">✗</div>
        <h1>❌ Connection Error</h1>
        <p>No authorization code received from Spotify.</p>
        <button class="close-btn" onclick="window.close()">Close Window</button>
    </div>
</body>
</html>
            "#;
            return Err((StatusCode::BAD_REQUEST, Html(error_html.to_string())));
        }
    };

    let state_param = match params.state {
        Some(state) => state,
        None => {
            let error_html = r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Connection Error - Musestruct</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }
        .error-icon {
            width: 80px;
            height: 80px;
            background: #ff6b6b;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-size: 40px;
            color: white;
        }
        h1 {
            color: #ff6b6b;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }
        p {
            color: #666;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }
        .close-btn {
            background: #ff6b6b;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-icon">✗</div>
        <h1>❌ Connection Error</h1>
        <p>No state parameter received from Spotify.</p>
        <button class="close-btn" onclick="window.close()">Close Window</button>
    </div>
</body>
</html>
            "#;
            return Err((StatusCode::BAD_REQUEST, Html(error_html.to_string())));
        }
    };

    // Extract user ID from state parameter (format: "uuid:user_id")
    let user_id = match state_param.split(':').nth(1) {
        Some(user_id_str) => {
            match uuid::Uuid::parse_str(user_id_str) {
                Ok(user_id) => user_id,
                Err(_) => {
                    let error_html = r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Connection Error - Musestruct</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }
        .error-icon {
            width: 80px;
            height: 80px;
            background: #ff6b6b;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-size: 40px;
            color: white;
        }
        h1 {
            color: #ff6b6b;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }
        p {
            color: #666;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }
        .close-btn {
            background: #ff6b6b;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-icon">✗</div>
        <h1>❌ Connection Error</h1>
        <p>Invalid state parameter received from Spotify.</p>
        <button class="close-btn" onclick="window.close()">Close Window</button>
    </div>
</body>
</html>
                    "#;
                    return Err((StatusCode::BAD_REQUEST, Html(error_html.to_string())));
                }
            }
        },
        None => {
            let error_html = r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Connection Error - Musestruct</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }
        .error-icon {
            width: 80px;
            height: 80px;
            background: #ff6b6b;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-size: 40px;
            color: white;
        }
        h1 {
            color: #ff6b6b;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }
        p {
            color: #666;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }
        .close-btn {
            background: #ff6b6b;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-icon">✗</div>
        <h1>❌ Connection Error</h1>
        <p>Invalid state parameter format received from Spotify.</p>
        <button class="close-btn" onclick="window.close()">Close Window</button>
    </div>
</body>
</html>
            "#;
            return Err((StatusCode::BAD_REQUEST, Html(error_html.to_string())));
        }
    };

    // Exchange authorization code for access token
    match exchange_spotify_code(&code, state.db(), user_id).await {
        Ok(_message) => {
            // Return a pretty HTML page instead of JSON
            let html = r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Connected - Musestruct</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1db954 0%, #1ed760 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }
        .success-icon {
            width: 80px;
            height: 80px;
            background: #1db954;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-size: 40px;
            color: white;
        }
        h1 {
            color: #1db954;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }
        p {
            color: #666;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }
        .close-btn {
            background: #1db954;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s;
        }
        .close-btn:hover {
            background: #1ed760;
        }
        .spotify-logo {
            width: 24px;
            height: 24px;
            margin-right: 8px;
            vertical-align: middle;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success-icon">✓</div>
        <h1>🎵 Spotify Connected!</h1>
        <p>Your Spotify account has been successfully connected to Musestruct. You can now enjoy your music across all your devices.</p>
        <button class="close-btn" onclick="window.close()">
            <svg class="spotify-logo" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12 12-5.4 12-12S18.66 0 12 0zm5.521 17.34c-.24.359-.66.48-1.021.24-2.82-1.74-6.36-2.101-10.561-1.141-.418.122-.779-.179-.899-.539-.12-.421.18-.78.54-.9 4.56-1.021 8.52-.6 11.64 1.32.42.18.479.659.301 1.02zm1.44-3.3c-.301.42-.841.6-1.262.3-3.239-1.98-8.159-2.58-11.939-1.38-.479.12-1.02-.12-1.14-.6-.12-.48.12-1.021.6-1.141C9.6 9.9 15 10.561 18.72 12.84c.361.181.54.78.241 1.2zm.12-3.36C15.24 8.4 8.82 8.16 5.16 9.301c-.6.179-1.2-.181-1.38-.721-.18-.601.18-1.2.72-1.381 4.26-1.26 11.28-1.02 15.721 1.621.539.3.719 1.02.42 1.56-.299.421-1.02.599-1.559.3z"/>
            </svg>
            Close Window
        </button>
    </div>
    <script>
        // Auto-close after 3 seconds
        setTimeout(() => {
            window.close();
        }, 3000);
    </script>
</body>
</html>
            "#;
            
            Ok(axum::response::Html(html.to_string()))
        },
        Err(err) => {
            // Return an error HTML page
            let html = format!(r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Connection Error - Musestruct</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a52 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }}
        .container {{
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 400px;
            width: 90%;
        }}
        .error-icon {{
            width: 80px;
            height: 80px;
            background: #ff6b6b;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 24px;
            font-size: 40px;
            color: white;
        }}
        h1 {{
            color: #ff6b6b;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }}
        p {{
            color: #666;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }}
        .error-details {{
            background: #f8f9fa;
            border-radius: 8px;
            padding: 16px;
            margin: 16px 0;
            font-family: monospace;
            font-size: 14px;
            color: #666;
            word-break: break-all;
        }}
        .close-btn {{
            background: #ff6b6b;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s;
        }}
        .close-btn:hover {{
            background: #ee5a52;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="error-icon">✗</div>
        <h1>❌ Connection Failed</h1>
        <p>There was an error connecting your Spotify account. Please try again.</p>
        <div class="error-details">{}</div>
        <button class="close-btn" onclick="window.close()">Close Window</button>
    </div>
</body>
</html>
            "#, err);
            
            Ok(axum::response::Html(html))
        }
    }
}

async fn exchange_spotify_code(
    code: &str,
    db: &sea_orm::DatabaseConnection,
    user_id: uuid::Uuid,
) -> Result<String, String> {
    let client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
    let client_secret = std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default();
    let redirect_uri = std::env::var("SPOTIFY_REDIRECT_URI").unwrap_or_else(|_| "http://127.0.0.1:8080/api/streaming/spotify/callback".to_string());

    if client_id.is_empty() || client_secret.is_empty() {
        return Err("Spotify credentials not configured".to_string());
    }

    let client = reqwest::Client::new();
    let auth_header = base64::encode(format!("{}:{}", client_id, client_secret));

    let mut form = std::collections::HashMap::new();
    form.insert("grant_type", "authorization_code");
    form.insert("code", code);
    form.insert("redirect_uri", &redirect_uri);

    let response = client
        .post("https://accounts.spotify.com/api/token")
        .header("Authorization", format!("Basic {}", auth_header))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .form(&form)
        .send()
        .await
        .map_err(|e| format!("Failed to exchange code: {}", e))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Spotify token exchange error: {}", error_text));
    }

    let token_response: serde_json::Value = response.json().await
        .map_err(|e| format!("Failed to parse token response: {}", e))?;

    let access_token = token_response["access_token"]
        .as_str()
        .ok_or("No access token in response")?
        .to_string();
    
    let refresh_token = token_response["refresh_token"]
        .as_str()
        .map(|s| s.to_string());

    let expires_in = token_response["expires_in"]
        .as_u64()
        .unwrap_or(3600) as i64;

    // Get user information from Spotify
    let user_info = get_spotify_user_info(&access_token).await?;
    let account_username = user_info.get("display_name")
        .and_then(|v| v.as_str())
        .or_else(|| user_info.get("id").and_then(|v| v.as_str()))
        .map(|s| s.to_string());

    // Save the authentication to the database
    let existing_service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user_id))
        .filter(StreamingServiceColumn::ServiceName.eq("spotify"))
        .one(db)
        .await
        .map_err(|e| format!("Database error: {}", e))?;

    let expires_at = Some((chrono::Utc::now() + chrono::Duration::seconds(expires_in)).naive_utc());

    match existing_service {
        Some(existing) => {
            // Update existing service
            let mut service: StreamingServiceActiveModel = existing.into();
            service.access_token = Set(Some(access_token));
            service.refresh_token = Set(refresh_token);
            service.expires_at = Set(expires_at);
            service.account_username = Set(account_username);
            service.is_active = Set(true);
            
            service.update(db).await
                .map_err(|e| format!("Failed to update Spotify connection: {}", e))?;
        },
        None => {
            // Create new service entry
            let new_service = StreamingServiceActiveModel {
                user_id: Set(user_id),
                service_name: Set("spotify".to_string()),
                access_token: Set(Some(access_token)),
                refresh_token: Set(refresh_token),
                expires_at: Set(expires_at),
                account_username: Set(account_username),
                is_active: Set(true),
                ..Default::default()
            };
            
            new_service.insert(db).await
                .map_err(|e| format!("Failed to save Spotify connection: {}", e))?;
        }
    }

    Ok("Successfully connected to Spotify".to_string())
}

#[derive(Deserialize)]
pub struct TransferPlaybackRequest {
    pub device_id: String,
}

pub async fn transfer_spotify_playback(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Json(request): Json<TransferPlaybackRequest>,
) -> Result<Json<ApiResponse<String>>, (StatusCode, Json<ApiResponse<()>>)> {
    // Get user's Spotify access token
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

    let access_token = match spotify_service {
        Some(service) => service.access_token.ok_or_else(|| (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error("No Spotify access token found".to_string()))
        ))?,
        None => {
            return Err((
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<()>::error("Spotify service not connected".to_string())),
            ));
        }
    };

    // Transfer playback to the specified device
    let client = reqwest::Client::new();
    let response = client
        .put("https://api.spotify.com/v1/me/player")
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({
            "device_ids": [request.device_id],
            "play": true
        }))
        .send()
        .await
        .map_err(|e| (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Failed to transfer playback: {}", e)))
        ))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Spotify API error: {}", error_text))),
        ));
    }

    Ok(Json(ApiResponse::success("Playback transferred successfully".to_string())))
}

pub async fn get_spotify_access_token(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<String>>, (StatusCode, Json<ApiResponse<()>>)> {
    // Get user's Spotify access token
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

    let access_token = match spotify_service {
        Some(service) => service.access_token.ok_or_else(|| (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error("No Spotify access token found".to_string()))
        ))?,
        None => {
            return Err((
                StatusCode::NOT_FOUND,
                Json(ApiResponse::<()>::error("Spotify service not connected".to_string())),
            ));
        }
    };

    Ok(Json(ApiResponse::success(access_token)))
}

#[derive(Deserialize)]
pub struct RefreshSpotifyTokenRequest {
    pub refresh_token: String,
}

#[derive(Serialize)]
pub struct RefreshSpotifyTokenResponse {
    pub access_token: String,
    pub expires_in: i64,
}

pub async fn refresh_spotify_token(
    State(state): State<AppState>,
    Json(request): Json<RefreshSpotifyTokenRequest>,
) -> Result<Json<ApiResponse<RefreshSpotifyTokenResponse>>, StatusCode> {
    let client_id = std::env::var("SPOTIFY_CLIENT_ID")
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let client_secret = std::env::var("SPOTIFY_CLIENT_SECRET")
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    let token_url = "https://accounts.spotify.com/api/token";
    let params = [
        ("grant_type", "refresh_token"),
        ("refresh_token", &request.refresh_token),
        ("client_id", &client_id),
        ("client_secret", &client_secret),
    ];
    
    let client = reqwest::Client::new();
    let response = client
        .post(token_url)
        .form(&params)
        .send()
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    if response.status().is_success() {
        let token_response: serde_json::Value = response
            .json()
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        
        let access_token = token_response["access_token"]
            .as_str()
            .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?
            .to_string();
        
        let expires_in = token_response["expires_in"]
            .as_i64()
            .unwrap_or(3600);
        
        Ok(Json(ApiResponse {
            success: true,
            data: Some(RefreshSpotifyTokenResponse {
                access_token,
                expires_in,
            }),
            message: Some("Spotify token refreshed successfully".to_string()),
        }))
    } else {
        Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("Failed to refresh Spotify token".to_string()),
        }))
    }
}

async fn get_spotify_user_info(access_token: &str) -> Result<serde_json::Value, String> {
    let client = reqwest::Client::new();
    
    let response = client
        .get("https://api.spotify.com/v1/me")
        .header("Authorization", format!("Bearer {}", access_token))
        .send()
        .await
        .map_err(|e| format!("Failed to get user info: {}", e))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Spotify user info error: {}", error_text));
    }

    let user_info: serde_json::Value = response.json().await
        .map_err(|e| format!("Failed to parse user info: {}", e))?;

    Ok(user_info)
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
        ServiceInfo {
            name: "server".to_string(),
            display_name: "Server".to_string(),
            supports_full_tracks: true,
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
        ConnectedServiceInfo {
            name: "server".to_string(),
            display_name: "Server".to_string(),
            is_connected: true, // Server is always "connected" as it's local
            connected_at: None, // No connection time for local server
            account_username: Some("Local Server".to_string()),
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

#[derive(Deserialize)]
pub struct GetBackendStreamUrlQuery {
    pub track_id: String,
    pub source: String,
    pub url: String,
    pub title: Option<String>,
    pub artist: Option<String>,
}

#[derive(Serialize)]
pub struct BackendStreamUrlResponse {
    pub stream_url: String,
    pub is_cached: bool,
}

pub async fn get_backend_stream_url(
    State(state): State<AppState>,
    Extension(_user): Extension<UserResponseDto>,
    Query(query): Query<GetBackendStreamUrlQuery>,
) -> Result<Json<ApiResponse<BackendStreamUrlResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    debug!("Getting backend stream URL for track {} from {}", query.track_id, query.source);

    // Handle server source differently - don't cache local files
    if query.source == "server" {
        // For server tracks, return the URL directly without caching
        let response = BackendStreamUrlResponse {
            stream_url: query.url,
            is_cached: false, // Server files are not cached, they're served directly
        };
        return Ok(Json(ApiResponse::success(response)));
    }

    // For other sources, use the caching streaming service
    match state.streaming_service
        .get_stream_url(&query.track_id, &query.source, &query.url, query.title.as_deref(), query.artist.as_deref())
        .await
    {
        Ok(stream_url) => {
            let response = BackendStreamUrlResponse {
                stream_url,
                is_cached: true, // For now, assume it's always cached
            };
            Ok(Json(ApiResponse::success(response)))
        }
        Err(e) => {
            error!("Failed to get backend stream URL: {}", e);
            Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error(format!("Failed to get stream URL: {}", e))),
            ))
        }
    }
}

// Get tracks from a streaming service playlist
pub async fn get_playlist_tracks(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Path(playlist_id): Path<String>,
    Query(params): Query<GetPlaylistTracksQuery>,
) -> Result<Json<ApiResponse<Vec<StreamingTrack>>>, (StatusCode, Json<ApiResponse<()>>)> {
    let service_name = params.service.as_deref().unwrap_or("spotify");
    
    let service = match get_authenticated_streaming_service(service_name, user.id, state.db()).await {
        Ok(service) => service,
        Err(err) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()>::error(err)),
            ));
        }
    };

    match service.get_playlist_tracks(&playlist_id, params.limit, params.offset).await {
        Ok(tracks) => Ok(Json(ApiResponse::success(tracks))),
        Err(err) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Failed to get playlist tracks: {}", err))),
        )),
    }
}

#[derive(Deserialize)]
pub struct GetPlaylistTracksQuery {
    pub service: Option<String>,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

// Stream local music files
pub async fn stream_local_file(
    axum::extract::Path(file_path_param): axum::extract::Path<String>,
    headers: HeaderMap,
) -> Result<Response, StatusCode> {
    use tokio::fs;
    use tokio::io::{AsyncReadExt, AsyncSeekExt};
    
    // Decode the file path (can include subdirectories)
    let decoded_path = urlencoding::decode(&file_path_param)
        .map_err(|_| StatusCode::BAD_REQUEST)?
        .into_owned();
    
    // Create path to the file in own_music directory
    let music_dir = std::env::current_dir()
        .unwrap_or_else(|_| std::path::PathBuf::from("."))
        .join("own_music");
    let file_path = music_dir.join(&decoded_path);
    
    // Security check: ensure the file is within the own_music directory
    if !file_path.starts_with(&music_dir) {
        return Err(StatusCode::FORBIDDEN);
    }
    
    // Check if file exists
    if !file_path.exists() {
        return Err(StatusCode::NOT_FOUND);
    }
    
    // Get file metadata
    let file_metadata = fs::metadata(&file_path).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let file_size = file_metadata.len() as usize;
    
    // Parse range header if present
    let range_header = headers.get(header::RANGE)
        .and_then(|h| h.to_str().ok());
    
    let (start, end) = if let Some(range) = range_header {
        if let Some((start_str, end_str)) = range.strip_prefix("bytes=").and_then(|r| r.split_once('-')) {
            let start = start_str.parse::<usize>().unwrap_or(0);
            let end = if end_str.is_empty() {
                file_size - 1
            } else {
                end_str.parse::<usize>().unwrap_or(file_size - 1).min(file_size - 1)
            };
            (start, end)
        } else {
            (0, file_size - 1)
        }
    } else {
        (0, file_size - 1)
    };
    
    // Open and read the file
    let mut file = fs::File::open(&file_path).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // Seek to start position
    file.seek(std::io::SeekFrom::Start(start as u64)).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // Read the range
    let mut buffer = vec![0u8; end - start + 1];
    let bytes_read = file.read_exact(&mut buffer).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    let content = buffer[..bytes_read].to_vec();
    
    // Determine content type based on file extension
    let content_type = match file_path.extension().and_then(|ext| ext.to_str()) {
        Some("mp3") => "audio/mpeg",
        Some("flac") => "audio/flac",
        Some("wav") => "audio/wav",
        Some("m4a") => "audio/mp4",
        Some("ogg") => "audio/ogg",
        _ => "application/octet-stream",
    };
    
    // Create response with proper headers
    let mut response_builder = Response::builder()
        .header(header::CONTENT_TYPE, content_type)
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::CACHE_CONTROL, "public, max-age=3600")
        .header(header::CONTENT_LENGTH, content.len());
    
    if range_header.is_some() {
        response_builder = response_builder
            .status(StatusCode::PARTIAL_CONTENT)
            .header(header::CONTENT_RANGE, format!("bytes {}-{}/{}", start, end, file_size));
    } else {
        response_builder = response_builder.status(StatusCode::OK);
    }
    
    response_builder
        .body(content.into())
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

// Stream local cover images
pub async fn stream_local_cover(
    axum::extract::Path(file_path_param): axum::extract::Path<String>,
    headers: HeaderMap,
) -> Result<Response, StatusCode> {
    use tokio::fs;
    use tokio::io::AsyncReadExt;
    
    // Decode the file path (can include subdirectories)
    let decoded_path = urlencoding::decode(&file_path_param)
        .map_err(|_| StatusCode::BAD_REQUEST)?
        .into_owned();
    
    // Create path to the file in own_music directory
    let music_dir = std::env::current_dir()
        .unwrap_or_else(|_| std::path::PathBuf::from("."))
        .join("own_music");
    let file_path = music_dir.join(&decoded_path);
    
    // Security check: ensure the file is within the own_music directory
    if !file_path.starts_with(&music_dir) {
        return Err(StatusCode::FORBIDDEN);
    }
    
    // Check if file exists and is an image
    if !file_path.exists() {
        return Err(StatusCode::NOT_FOUND);
    }
    
    let extension = file_path.extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_lowercase();
    
    let content_type = match extension.as_str() {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "gif" => "image/gif",
        "bmp" => "image/bmp",
        _ => return Err(StatusCode::UNSUPPORTED_MEDIA_TYPE),
    };
    
    // Read the entire image file
    let content = fs::read(&file_path).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // Create response with proper headers
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CACHE_CONTROL, "public, max-age=86400") // Cache for 24 hours
        .header(header::CONTENT_LENGTH, content.len())
        .body(content.into())
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}
