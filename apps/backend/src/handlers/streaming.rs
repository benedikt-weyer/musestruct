use axum::{
    extract::{State, Query, Extension, Path},
    http::{StatusCode, HeaderMap, header},
    response::{Json, Html, Response},
};
use axum_extra::extract::Query as MultiValueQuery;
use tracing::{debug, error};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use sea_orm::{EntityTrait, Set, ActiveModelTrait, ColumnTrait, PaginatorTrait, QueryFilter, QueryOrder, QuerySelect};

use crate::services::streaming::{LocalMusicService, QobuzService, SearchResults, SpotifyService, StreamingService, StreamingTrack, TidalService};
use crate::services::streaming_service::StreamingService as BackendStreamingService;
use crate::services::{COVER_CACHE_TTL_SECONDS, fetch_cached_provider_cover, normalize_search_results, normalize_streaming_track, normalize_streaming_tracks};
use crate::models::{
    SearchQuery, ServerAlbumColumn, ServerAlbumEntity, ServerAlbumTrackColumn, ServerAlbumTrackEntity,
    ServerPlaylistColumn, ServerPlaylistEntity, ServerPlaylistTrackColumn, ServerPlaylistTrackEntity,
    ServerTrackColumn, ServerTrackEntity, StreamingServiceActiveModel, StreamingServiceColumn,
    StreamingServiceEntity, UserResponseDto,
}; 
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
    pub library: Option<String>, // "true" for library search
}

#[derive(Deserialize)]
pub struct GetStreamUrlQuery {
    pub track_id: String,
    pub quality: Option<String>,
    pub service: Option<String>,
}

#[derive(Deserialize)]
pub struct GetStreamingTrackQuery {
    pub track_id: String,
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
        "tidal" => {
            let service = TidalService::new(
                std::env::var("TIDAL_CLIENT_ID").unwrap_or_default(),
                std::env::var("TIDAL_CLIENT_SECRET").unwrap_or_default(),
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

            let (access_token, refresh_token) = get_valid_spotify_tokens(user_id, db).await?;

            Ok(Box::new(
                SpotifyService::new(client_id, client_secret).with_tokens(access_token, refresh_token),
            ))
        },
        "tidal" => {
            let client_id = std::env::var("TIDAL_CLIENT_ID").unwrap_or_default();
            let client_secret = std::env::var("TIDAL_CLIENT_SECRET").unwrap_or_default();

            if client_id.is_empty() {
                return Err("Tidal client ID not configured".to_string());
            }

            let (access_token, refresh_token) = get_valid_tidal_tokens(user_id, db).await?;
            Ok(Box::new(
                TidalService::new(client_id, client_secret).with_tokens(access_token, refresh_token),
            ))
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

struct SpotifyTokenRefreshResult {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: i64,
}

struct TidalTokenRefreshResult {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: i64,
}

#[derive(Debug, Deserialize)]
struct TidalTokenExchangeResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
    user_id: Option<serde_json::Value>,
}

async fn request_spotify_token_refresh(refresh_token: &str) -> Result<SpotifyTokenRefreshResult, String> {
    let client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
    let client_secret = std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default();

    if client_id.is_empty() || client_secret.is_empty() {
        return Err("Spotify credentials not configured".to_string());
    }

    let token_url = "https://accounts.spotify.com/api/token";
    let params = [
        ("grant_type", "refresh_token"),
        ("refresh_token", refresh_token),
        ("client_id", &client_id),
        ("client_secret", &client_secret),
    ];

    let client = reqwest::Client::new();
    let response = client
        .post(token_url)
        .form(&params)
        .send()
        .await
        .map_err(|error| format!("Failed to refresh Spotify token: {}", error))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Spotify token refresh error: {}", error_text));
    }

    let token_response: serde_json::Value = response
        .json()
        .await
        .map_err(|error| format!("Failed to parse Spotify token refresh response: {}", error))?;

    let access_token = token_response["access_token"]
        .as_str()
        .ok_or("Spotify refresh response did not contain an access token")?
        .to_string();
    let refresh_token = token_response["refresh_token"]
        .as_str()
        .map(|value| value.to_string());
    let expires_in = token_response["expires_in"].as_i64().unwrap_or(3600);

    Ok(SpotifyTokenRefreshResult {
        access_token,
        refresh_token,
        expires_in,
    })
}

pub(crate) async fn get_valid_spotify_tokens(
    user_id: uuid::Uuid,
    db: &sea_orm::DatabaseConnection,
) -> Result<(String, Option<String>), String> {
    let user_service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user_id))
        .filter(StreamingServiceColumn::ServiceName.eq("spotify"))
        .filter(StreamingServiceColumn::IsActive.eq(true))
        .one(db)
        .await
        .map_err(|error| format!("Database error: {}", error))?;

    let service = user_service.ok_or_else(|| {
        "Spotify service not connected for this user. Please connect to Spotify first.".to_string()
    })?;

    let should_refresh = service.access_token.is_none()
        || service
            .expires_at
            .map(|expires_at| expires_at <= (chrono::Utc::now() + chrono::Duration::seconds(60)).naive_utc())
            .unwrap_or(false);

    if !should_refresh {
        return Ok((
            service
                .access_token
                .ok_or_else(|| "No access token found for Spotify service".to_string())?,
            service.refresh_token,
        ));
    }

    let existing_refresh_token = service
        .refresh_token
        .clone()
        .ok_or_else(|| "Spotify access token expired and no refresh token is available. Please reconnect Spotify.".to_string())?;
    let refreshed_tokens = request_spotify_token_refresh(&existing_refresh_token).await?;
    let next_refresh_token = refreshed_tokens
        .refresh_token
        .clone()
        .or_else(|| Some(existing_refresh_token.clone()));
    let expires_at = Some(
        (chrono::Utc::now() + chrono::Duration::seconds(refreshed_tokens.expires_in)).naive_utc(),
    );

    let mut active_service: StreamingServiceActiveModel = service.into();
    active_service.access_token = Set(Some(refreshed_tokens.access_token.clone()));
    active_service.refresh_token = Set(next_refresh_token.clone());
    active_service.expires_at = Set(expires_at);
    active_service.is_active = Set(true);
    active_service
        .update(db)
        .await
        .map_err(|error| format!("Failed to update Spotify credentials: {}", error))?;

    Ok((refreshed_tokens.access_token, next_refresh_token))
}

fn normalize_tidal_scopes() -> String {
    [
        "collection.read",
        "playback",
        "playlists.read",
        "search.read",
        "user.read",
    ]
    .join(" ")
}

fn resolve_tidal_redirect_uri(headers: &HeaderMap) -> String {
    match std::env::var("TIDAL_REDIRECT_URI") {
        Ok(redirect_uri) if !redirect_uri.trim().is_empty() => redirect_uri,
        _ => {
            let host = header_string(headers, "x-forwarded-host")
                .or_else(|| headers.get(header::HOST).and_then(|value| value.to_str().ok()).map(|value| value.to_string()))
                .unwrap_or_else(|| "127.0.0.1:8080".to_string());
            let scheme = header_string(headers, "x-forwarded-proto")
                .unwrap_or_else(|| infer_request_scheme(&host).to_string());

            format!("{}://{}/api/streaming/tidal/callback", scheme, host)
        }
    }
}

fn encode_tidal_state(
    user_id: uuid::Uuid,
    code_verifier: &str,
    client_redirect_url: Option<&str>,
) -> String {
    let nonce = uuid::Uuid::new_v4();
    let encoded_verifier = base64::encode(code_verifier);
    let encoded_redirect_url = client_redirect_url.map(base64::encode).unwrap_or_default();

    format!("{}:{}:{}:{}", nonce, user_id, encoded_verifier, encoded_redirect_url)
}

fn decode_tidal_state(state: &str) -> Result<(uuid::Uuid, String, Option<String>), String> {
    let mut parts = state.splitn(4, ':');

    let _nonce = parts
        .next()
        .ok_or_else(|| "Invalid state parameter format received from Tidal.".to_string())?;

    let user_id = parts
        .next()
        .ok_or_else(|| "Invalid state parameter format received from Tidal.".to_string())
        .and_then(|user_id_str| {
            uuid::Uuid::parse_str(user_id_str)
                .map_err(|_| "Invalid state parameter received from Tidal.".to_string())
        })?;

    let encoded_verifier = parts
        .next()
        .ok_or_else(|| "Invalid state parameter format received from Tidal.".to_string())?;
    let verifier_bytes = base64::decode(encoded_verifier)
        .map_err(|_| "Invalid state parameter format received from Tidal.".to_string())?;
    let code_verifier = String::from_utf8(verifier_bytes)
        .map_err(|_| "Invalid state parameter format received from Tidal.".to_string())?;

    let client_redirect_url = match parts.next() {
        Some(encoded_redirect_url) if !encoded_redirect_url.is_empty() => {
            let decoded_bytes = base64::decode(encoded_redirect_url)
                .map_err(|_| "Invalid state parameter format received from Tidal.".to_string())?;
            let decoded_redirect_url = String::from_utf8(decoded_bytes)
                .map_err(|_| "Invalid state parameter format received from Tidal.".to_string())?;
            normalize_client_redirect_url(Some(decoded_redirect_url))?
        }
        _ => None,
    };

    Ok((user_id, code_verifier, client_redirect_url))
}

fn build_tidal_app_redirect_url(base_redirect_url: &str, status: &str, message: &str) -> String {
    let separator = if base_redirect_url.contains('?') { '&' } else { '?' };
    format!(
        "{}{separator}status={}&message={}&service=tidal",
        base_redirect_url,
        urlencoding::encode(status),
        urlencoding::encode(message),
    )
}

fn build_tidal_app_redirect_html(target_url: &str, title: &str, message: &str, accent_color: &str) -> String {
    format!(
        r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{}</title>
    <meta http-equiv="refresh" content="0;url={}">
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, {} 0%, #0f172a 100%);
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
            box-shadow: 0 20px 40px rgba(0,0,0,0.12);
            text-align: center;
            max-width: 420px;
            width: 90%;
        }}
        h1 {{
            color: #0f172a;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }}
        p {{
            color: #475569;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }}
        .open-btn {{
            display: inline-block;
            background: {};
            color: white;
            text-decoration: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
        }}
    </style>
    <script>
        window.location.replace({});
    </script>
</head>
<body>
    <div class="container">
        <h1>{}</h1>
        <p>{}</p>
        <a class="open-btn" href="{}">Return to the app</a>
    </div>
</body>
</html>
        "#,
        title,
        target_url,
        accent_color,
        accent_color,
        serde_json::to_string(target_url).unwrap_or_else(|_| "\"\"".to_string()),
        title,
        message,
        target_url,
    )
}

fn tidal_error_page(title: &str, message: &str, accent_color: &str) -> String {
    format!(
        r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{}</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, {} 0%, #0f172a 100%);
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
            box-shadow: 0 20px 40px rgba(0,0,0,0.12);
            text-align: center;
            max-width: 420px;
            width: 90%;
        }}
        h1 {{
            color: {};
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }}
        p {{
            color: #475569;
            margin: 0;
            line-height: 1.5;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>{}</h1>
        <p>{}</p>
    </div>
</body>
</html>
        "#,
        title,
        accent_color,
        accent_color,
        title,
        message,
    )
}

async fn request_tidal_token_refresh(refresh_token: &str) -> Result<TidalTokenRefreshResult, String> {
    let client_id = std::env::var("TIDAL_CLIENT_ID").unwrap_or_default();
    let client_secret = std::env::var("TIDAL_CLIENT_SECRET").unwrap_or_default();
    let client_unique_key = std::env::var("TIDAL_CLIENT_UNIQUE_KEY").unwrap_or_default();
    let scopes = normalize_tidal_scopes();

    if client_id.is_empty() {
        return Err("Tidal client ID not configured".to_string());
    }

    let mut form = vec![
        ("client_id", client_id.clone()),
        ("grant_type", "refresh_token".to_string()),
        ("refresh_token", refresh_token.to_string()),
    ];

    if !client_secret.is_empty() {
        form.push(("client_secret", client_secret));
    }

    if !client_unique_key.is_empty() {
        form.push(("client_unique_key", client_unique_key));
    }

    if !scopes.is_empty() {
        form.push(("scope", scopes));
    }

    let client = reqwest::Client::new();
    let response = client
        .post("https://auth.tidal.com/v1/oauth2/token")
        .form(&form)
        .send()
        .await
        .map_err(|error| format!("Failed to refresh Tidal token: {}", error))?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err(format!("Tidal token refresh error: {}", error_text));
    }

    let token_response: TidalTokenExchangeResponse = response
        .json()
        .await
        .map_err(|error| format!("Failed to parse Tidal token refresh response: {}", error))?;

    Ok(TidalTokenRefreshResult {
        access_token: token_response.access_token,
        refresh_token: token_response.refresh_token,
        expires_in: token_response.expires_in.unwrap_or(3600),
    })
}

pub(crate) async fn get_valid_tidal_tokens(
    user_id: uuid::Uuid,
    db: &sea_orm::DatabaseConnection,
) -> Result<(String, Option<String>), String> {
    let user_service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user_id))
        .filter(StreamingServiceColumn::ServiceName.eq("tidal"))
        .filter(StreamingServiceColumn::IsActive.eq(true))
        .one(db)
        .await
        .map_err(|error| format!("Database error: {}", error))?;

    let service = user_service.ok_or_else(|| {
        "Tidal service not connected for this user. Please connect to Tidal first.".to_string()
    })?;

    let should_refresh = service.access_token.is_none()
        || service
            .expires_at
            .map(|expires_at| expires_at <= (chrono::Utc::now() + chrono::Duration::seconds(60)).naive_utc())
            .unwrap_or(false);

    if !should_refresh {
        return Ok((
            service
                .access_token
                .ok_or_else(|| "No access token found for Tidal service".to_string())?,
            service.refresh_token,
        ));
    }

    let existing_refresh_token = service
        .refresh_token
        .clone()
        .ok_or_else(|| "Tidal access token expired and no refresh token is available. Please reconnect Tidal.".to_string())?;
    let refreshed_tokens = request_tidal_token_refresh(&existing_refresh_token).await?;
    let next_refresh_token = refreshed_tokens
        .refresh_token
        .clone()
        .or_else(|| Some(existing_refresh_token.clone()));
    let expires_at = Some(
        (chrono::Utc::now() + chrono::Duration::seconds(refreshed_tokens.expires_in)).naive_utc(),
    );

    let mut active_service: StreamingServiceActiveModel = service.into();
    active_service.access_token = Set(Some(refreshed_tokens.access_token.clone()));
    active_service.refresh_token = Set(next_refresh_token.clone());
    active_service.expires_at = Set(expires_at);
    active_service.is_active = Set(true);
    active_service
        .update(db)
        .await
        .map_err(|error| format!("Failed to update Tidal credentials: {}", error))?;

    Ok((refreshed_tokens.access_token, next_refresh_token))
}

pub async fn search_music(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    MultiValueQuery(params): MultiValueQuery<StreamingSearchQuery>,
) -> Result<Json<ApiResponse<SearchResults>>, (StatusCode, Json<ApiResponse<()>>)> {
    // Determine which services to search
    let mut services_to_search = if let Some(services) = &params.services {
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

    services_to_search.sort();
    services_to_search.dedup();

    let mut all_tracks = Vec::new();
    let mut all_albums = Vec::new();
    let mut all_playlists = Vec::new();
    let mut total_results = 0;
    let mut search_errors = Vec::new();

    // Determine search type and mode
    let search_type = params.r#type.as_deref();
    let is_all_types_search = search_type.is_none() || search_type == Some("all");
    let is_library_search = params.library.as_deref() == Some("true");
    let requested_offset = params.offset.unwrap_or(0);
    let requested_limit = params.limit.unwrap_or(20);
    let use_global_pagination = services_to_search.len() > 1;
    let per_service_offset = if use_global_pagination {
        Some(0)
    } else {
        params.offset
    };
    let per_service_limit = if use_global_pagination {
        Some(requested_offset.saturating_add(requested_limit))
    } else {
        params.limit
    };
    println!(
        "Backend: Search type: {}, Library search: {}",
        search_type.unwrap_or("all"),
        is_library_search
    );
    println!("Backend: Services to search: {:?}", services_to_search);

    // Search each service
    for service_name in &services_to_search {
        if service_name == "server" {
            match search_server_catalog(
                state.db(),
                user.id,
                &params.q,
                search_type,
                is_library_search,
                per_service_limit,
                per_service_offset,
            )
            .await
            {
                Ok(results) => {
                    all_tracks.extend(results.tracks);
                    all_albums.extend(results.albums);
                    all_playlists.extend(results.playlists);
                    total_results += results.total;
                }
                Err(err) => {
                    search_errors.push(format!("{}: {}", service_name, err));
                }
            }

            continue;
        }

        match get_authenticated_streaming_service(service_name, user.id, state.db()).await {
            Ok(service) => {
                if is_library_search {
                    if is_all_types_search {
                        for library_type in ["track", "album", "playlist"] {
                            println!(
                                "Backend: Searching library on {} for query: {} with type: {}",
                                service_name,
                                params.q,
                                library_type
                            );
                            match service
                                .search_library(
                                    &params.q,
                                    Some(library_type),
                                    per_service_limit,
                                    per_service_offset,
                                )
                                .await
                            {
                                Ok(results) => {
                                    all_tracks.extend(results.tracks);
                                    all_albums.extend(results.albums);
                                    all_playlists.extend(results.playlists);
                                    total_results += results.total;
                                }
                                Err(err) => {
                                    println!(
                                        "Backend: Error searching library on {} for type {}: {}",
                                        service_name,
                                        library_type,
                                        err
                                    );
                                    search_errors.push(format!("{} {}: {}", service_name, library_type, err));
                                }
                            }
                        }
                    } else {
                        let search_type = search_type.unwrap();
                        println!("Backend: Searching library on {} for query: {} with type: {}", service_name, params.q, search_type);
                        match service.search_library(&params.q, Some(search_type), per_service_limit, per_service_offset).await {
                            Ok(results) => {
                                all_tracks.extend(results.tracks);
                                all_albums.extend(results.albums);
                                all_playlists.extend(results.playlists);
                                total_results += results.total;
                            },
                            Err(err) => {
                                println!("Backend: Error searching library on {}: {}", service_name, err);
                                search_errors.push(format!("{}: {}", service_name, err));
                            }
                        }
                    }
                } else if is_all_types_search {
                    match service.search(&params.q, per_service_limit, per_service_offset).await {
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

                    match service.search_playlists(&params.q, per_service_limit, per_service_offset).await {
                        Ok(playlists) => {
                            let playlist_count = playlists.len() as u32;
                            all_playlists.extend(playlists);
                            total_results += playlist_count;
                        },
                        Err(err) => {
                            search_errors.push(format!("{} playlists: {}", service_name, err));
                        }
                    }
                } else if search_type == Some("playlist") {
                    // Search for playlists
                    println!("Backend: Searching playlists on {} for query: {}", service_name, params.q);
                    match service.search_playlists(&params.q, per_service_limit, per_service_offset).await {
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
                    match service.search(&params.q, per_service_limit, per_service_offset).await {
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

    match search_type {
        Some("album") => {
            all_tracks.clear();
            all_playlists.clear();
        }
        Some("playlist") => {
            all_tracks.clear();
            all_albums.clear();
        }
        Some("track") => {
            all_albums.clear();
            all_playlists.clear();
        }
        _ => {}
    }

    all_tracks.sort_by(|a, b| {
        a.title
            .to_lowercase()
            .cmp(&b.title.to_lowercase())
            .then_with(|| a.title.cmp(&b.title))
    });
    all_albums.sort_by(|a, b| {
        a.title
            .to_lowercase()
            .cmp(&b.title.to_lowercase())
            .then_with(|| a.title.cmp(&b.title))
    });
    all_playlists.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then_with(|| a.name.cmp(&b.name))
    });

    if !use_global_pagination {
        total_results = match search_type {
            Some("album") => all_albums.len() as u32,
            Some("playlist") => all_playlists.len() as u32,
            Some("track") => all_tracks.len() as u32,
            _ => all_tracks.len() as u32 + all_albums.len() as u32 + all_playlists.len() as u32,
        };
    }

    if use_global_pagination {
        let start = requested_offset as usize;
        let end = start.saturating_add(requested_limit as usize);

        all_tracks = all_tracks.into_iter().skip(start).take(end.saturating_sub(start)).collect();
        all_albums = all_albums.into_iter().skip(start).take(end.saturating_sub(start)).collect();
        all_playlists = all_playlists.into_iter().skip(start).take(end.saturating_sub(start)).collect();
    } else {
        let limit = requested_limit as usize;
        if all_tracks.len() > limit {
            all_tracks.truncate(limit);
        }
        if all_albums.len() > limit {
            all_albums.truncate(limit);
        }
        if all_playlists.len() > limit {
            all_playlists.truncate(limit);
        }
    }

    let combined_results = normalize_search_results(SearchResults {
        tracks: all_tracks,
        albums: all_albums,
        playlists: all_playlists.clone(),
        total: total_results,
        offset: requested_offset,
        limit: requested_limit,
    });

    println!("Backend: Returning search results - {} tracks, {} albums, {} playlists", 
             combined_results.tracks.len(), combined_results.albums.len(), combined_results.playlists.len());
    
    // Debug: Print first playlist if any
    if !all_playlists.is_empty() {
        println!("Backend: First playlist: {:?}", &all_playlists[0]);
    }

    Ok(Json(ApiResponse::success(combined_results)))
}

async fn search_server_catalog(
    db: &sea_orm::DatabaseConnection,
    user_id: uuid::Uuid,
    query: &str,
    search_type: Option<&str>,
    _is_library_search: bool,
    limit: Option<u32>,
    offset: Option<u32>,
) -> Result<SearchResults, String> {
    let normalized_query = query.trim().to_lowercase();
    let limit = limit.unwrap_or(20) as u64;
    let offset = offset.unwrap_or(0) as u64;
    let all_types = search_type.is_none() || search_type == Some("all");

    let tracks = if all_types || search_type == Some("track") {
        search_server_tracks(db, user_id, &normalized_query, limit, offset)
            .await
            .map_err(|error| error.to_string())?
    } else {
        Vec::new()
    };

    let albums = if all_types || search_type == Some("album") {
        search_server_albums(db, user_id, &normalized_query, limit, offset)
            .await
            .map_err(|error| error.to_string())?
    } else {
        Vec::new()
    };

    let playlists = if all_types || search_type == Some("playlist") {
        search_server_playlists(db, user_id, &normalized_query, limit, offset)
            .await
            .map_err(|error| error.to_string())?
    } else {
        Vec::new()
    };

    let total = match search_type {
        Some("track") => tracks.len() as u32,
        Some("album") => albums.len() as u32,
        Some("playlist") => playlists.len() as u32,
        _ => (tracks.len() + albums.len() + playlists.len()) as u32,
    };

    Ok(SearchResults {
        tracks,
        albums,
        playlists,
        total,
        offset: offset as u32,
        limit: limit as u32,
    })
}

async fn search_server_tracks(
    db: &sea_orm::DatabaseConnection,
    user_id: uuid::Uuid,
    normalized_query: &str,
    limit: u64,
    offset: u64,
) -> anyhow::Result<Vec<StreamingTrack>> {
    let mut query = ServerTrackEntity::find().filter(ServerTrackColumn::UserId.eq(user_id));

    if !normalized_query.is_empty() {
        query = query.filter(
            ServerTrackColumn::Title
                .contains(normalized_query)
                .or(ServerTrackColumn::Artist.contains(normalized_query))
                .or(ServerTrackColumn::AlbumName.contains(normalized_query))
                .or(ServerTrackColumn::ProviderTrackId.contains(normalized_query)),
        );
    }

    let rows = query
        .order_by_asc(ServerTrackColumn::Artist)
        .order_by_asc(ServerTrackColumn::Title)
        .offset(offset)
        .offset(offset)
        .limit(limit)
        .all(db)
        .await?;

    Ok(rows
        .into_iter()
        .map(|row| StreamingTrack {
            id: row.provider_track_id,
            title: row.title,
            artist: row.artist,
            album: row.album_name.unwrap_or_default(),
            duration: row.duration,
            stream_url: None,
            cover_url: row.cover_url,
            quality: Some("Original".to_string()),
            source: "server".to_string(),
            bitrate: None,
            sample_rate: None,
            bit_depth: None,
        })
        .collect())
}

async fn search_server_albums(
    db: &sea_orm::DatabaseConnection,
    user_id: uuid::Uuid,
    normalized_query: &str,
    limit: u64,
    offset: u64,
) -> anyhow::Result<Vec<crate::services::streaming::StreamingAlbum>> {
    let mut query = ServerAlbumEntity::find().filter(ServerAlbumColumn::UserId.eq(user_id));

    if !normalized_query.is_empty() {
        query = query.filter(
            ServerAlbumColumn::Name
                .contains(normalized_query)
                .or(ServerAlbumColumn::Artist.contains(normalized_query)),
        );
    }

    let albums = query
        .order_by_asc(ServerAlbumColumn::Artist)
        .order_by_asc(ServerAlbumColumn::Name)
        .offset(offset)
        .limit(limit)
        .all(db)
        .await?;

    let mut results = Vec::with_capacity(albums.len());
    for album in albums {
        let album_track_rows = ServerAlbumTrackEntity::find()
            .filter(ServerAlbumTrackColumn::AlbumId.eq(album.id))
            .order_by_asc(ServerAlbumTrackColumn::Position)
            .all(db)
            .await?;
        let track_ids = album_track_rows.iter().map(|row| row.track_id).collect::<Vec<_>>();
        let tracks = if track_ids.is_empty() {
            Vec::new()
        } else {
            let track_map = ServerTrackEntity::find()
                .filter(ServerTrackColumn::Id.is_in(track_ids.clone()))
                .all(db)
                .await?
                .into_iter()
                .map(|row| (row.id, row))
                .collect::<HashMap<_, _>>();

            album_track_rows
                .into_iter()
                .filter_map(|join_row| track_map.get(&join_row.track_id))
                .map(|track| StreamingTrack {
                    id: track.provider_track_id.clone(),
                    title: track.title.clone(),
                    artist: track.artist.clone(),
                    album: track.album_name.clone().unwrap_or_default(),
                    duration: track.duration,
                    stream_url: None,
                    cover_url: track.cover_url.clone(),
                    quality: Some("Original".to_string()),
                    source: "server".to_string(),
                    bitrate: None,
                    sample_rate: None,
                    bit_depth: None,
                })
                .collect()
        };

        results.push(crate::services::streaming::StreamingAlbum {
            id: album.provider_album_id,
            title: album.name,
            artist: album.artist,
            release_date: album.release_date,
            cover_url: album.cover_url,
            tracks,
            source: "server".to_string(),
        });
    }

    Ok(results)
}

async fn search_server_playlists(
    db: &sea_orm::DatabaseConnection,
    user_id: uuid::Uuid,
    normalized_query: &str,
    limit: u64,
    offset: u64,
) -> anyhow::Result<Vec<crate::services::streaming::StreamingPlaylist>> {
    let mut query = ServerPlaylistEntity::find().filter(ServerPlaylistColumn::UserId.eq(user_id));

    if !normalized_query.is_empty() {
        query = query.filter(
            ServerPlaylistColumn::Name
                .contains(normalized_query)
                .or(ServerPlaylistColumn::Description.contains(normalized_query))
                .or(ServerPlaylistColumn::OwnerName.contains(normalized_query)),
        );
    }

    let playlists = query
        .order_by_asc(ServerPlaylistColumn::Name)
        .offset(offset)
        .limit(limit)
        .all(db)
        .await?;

    let mut results = Vec::with_capacity(playlists.len());
    for playlist in playlists {
        let track_count = ServerPlaylistTrackEntity::find()
            .filter(ServerPlaylistTrackColumn::PlaylistId.eq(playlist.id))
            .count(db)
            .await? as u32;

        results.push(crate::services::streaming::StreamingPlaylist {
            id: playlist.provider_playlist_id,
            name: playlist.name,
            description: playlist.description,
            owner: playlist.owner_name.unwrap_or_else(|| "Local".to_string()),
            source: "server".to_string(),
            cover_url: playlist.cover_url,
            track_count,
            is_public: false,
            external_url: None,
        });
    }

    Ok(results)
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

pub async fn get_streaming_track(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(params): Query<GetStreamingTrackQuery>,
) -> Result<Json<ApiResponse<StreamingTrack>>, (StatusCode, Json<ApiResponse<()>>)> {
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

    match service.get_track(&params.track_id).await {
        Ok(track) => Ok(Json(ApiResponse::success(normalize_streaming_track(track)))),
        Err(err) => Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error(format!("Failed to get track: {}", err))),
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
pub struct SpotifyAuthUrlQuery {
    pub redirect_url: Option<String>,
}

#[derive(Deserialize)]
pub struct TidalAuthUrlQuery {
    pub redirect_url: Option<String>,
}

#[derive(Deserialize)]
pub struct SpotifyCallbackQuery {
    pub code: Option<String>,
    pub state: Option<String>,
    pub error: Option<String>,
}

#[derive(Deserialize)]
pub struct TidalCallbackQuery {
    pub code: Option<String>,
    pub state: Option<String>,
    pub error: Option<String>,
}

fn header_string(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.split(',').next().unwrap_or(value).trim().to_string())
        .filter(|value| !value.is_empty())
}

fn infer_request_scheme(host: &str) -> &'static str {
    let hostname = host.split(':').next().unwrap_or(host);
    let is_local = hostname.eq_ignore_ascii_case("localhost")
        || hostname.starts_with("127.")
        || hostname.starts_with("10.")
        || hostname.starts_with("192.168.")
        || hostname.starts_with("172.");

    if is_local {
        "http"
    } else {
        "https"
    }
}

fn resolve_spotify_redirect_uri(headers: &HeaderMap) -> String {
    match std::env::var("SPOTIFY_REDIRECT_URI") {
        Ok(redirect_uri) if !redirect_uri.trim().is_empty() => redirect_uri,
        _ => {
            let host = header_string(headers, "x-forwarded-host")
                .or_else(|| headers.get(header::HOST).and_then(|value| value.to_str().ok()).map(|value| value.to_string()))
                .unwrap_or_else(|| "127.0.0.1:8080".to_string());
            let scheme = header_string(headers, "x-forwarded-proto")
                .unwrap_or_else(|| infer_request_scheme(&host).to_string());

            format!("{}://{}/api/streaming/spotify/callback", scheme, host)
        }
    }
}

fn normalize_client_redirect_url(redirect_url: Option<String>) -> Result<Option<String>, String> {
    let Some(redirect_url) = redirect_url else {
        return Ok(None);
    };

    let redirect_url = redirect_url.trim();

    if redirect_url.is_empty() {
        return Ok(None);
    }

    if !redirect_url.contains("://") || redirect_url.chars().any(char::is_whitespace) {
        return Err("Redirect URL must be an absolute URL like musestruct://spotify".to_string());
    }

    Ok(Some(redirect_url.to_string()))
}

fn encode_spotify_state(user_id: uuid::Uuid, client_redirect_url: Option<&str>) -> String {
    let nonce = uuid::Uuid::new_v4();
    let encoded_redirect_url = client_redirect_url
        .map(base64::encode)
        .unwrap_or_default();

    format!("{}:{}:{}", nonce, user_id, encoded_redirect_url)
}

fn decode_spotify_state(state: &str) -> Result<(uuid::Uuid, Option<String>), String> {
    let mut parts = state.splitn(3, ':');

    let _nonce = parts
        .next()
        .ok_or_else(|| "Invalid state parameter format received from Spotify.".to_string())?;

    let user_id = parts
        .next()
        .ok_or_else(|| "Invalid state parameter format received from Spotify.".to_string())
        .and_then(|user_id_str| {
            uuid::Uuid::parse_str(user_id_str)
                .map_err(|_| "Invalid state parameter received from Spotify.".to_string())
        })?;

    let client_redirect_url = match parts.next() {
        Some(encoded_redirect_url) if !encoded_redirect_url.is_empty() => {
            let decoded_bytes = base64::decode(encoded_redirect_url)
                .map_err(|_| "Invalid state parameter format received from Spotify.".to_string())?;
            let decoded_redirect_url = String::from_utf8(decoded_bytes)
                .map_err(|_| "Invalid state parameter format received from Spotify.".to_string())?;
            normalize_client_redirect_url(Some(decoded_redirect_url))?
        }
        _ => None,
    };

    Ok((user_id, client_redirect_url))
}

fn build_spotify_app_redirect_url(base_redirect_url: &str, status: &str, message: &str) -> String {
    let separator = if base_redirect_url.contains('?') { '&' } else { '?' };
    format!(
        "{}{separator}status={}&message={}&service=spotify",
        base_redirect_url,
        urlencoding::encode(status),
        urlencoding::encode(message),
    )
}

fn build_spotify_app_redirect_html(target_url: &str, title: &str, message: &str, accent_color: &str) -> String {
    format!(
        r#"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{}</title>
    <meta http-equiv="refresh" content="0;url={}">
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, {} 0%, #0f172a 100%);
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
            box-shadow: 0 20px 40px rgba(0,0,0,0.12);
            text-align: center;
            max-width: 420px;
            width: 90%;
        }}
        h1 {{
            color: #0f172a;
            margin: 0 0 16px 0;
            font-size: 28px;
            font-weight: 700;
        }}
        p {{
            color: #475569;
            margin: 0 0 24px 0;
            line-height: 1.5;
        }}
        .open-btn {{
            display: inline-block;
            background: {};
            color: white;
            text-decoration: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
        }}
    </style>
    <script>
        window.location.replace({});
    </script>
</head>
<body>
    <div class="container">
        <h1>{}</h1>
        <p>{}</p>
        <a class="open-btn" href="{}">Return to the app</a>
    </div>
</body>
</html>
        "#,
        title,
        target_url,
        accent_color,
        accent_color,
        serde_json::to_string(target_url).unwrap_or_else(|_| "\"\"".to_string()),
        title,
        message,
        target_url,
    )
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
    Query(query): Query<SpotifyAuthUrlQuery>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<SpotifyAuthUrlResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
    let redirect_uri = resolve_spotify_redirect_uri(&headers);
    let client_redirect_url = normalize_client_redirect_url(query.redirect_url)
        .map_err(|error| {
            (
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()>::error(error)),
            )
        })?;
    
    if client_id.is_empty() {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error("Spotify client ID not configured".to_string())),
        ));
    }

    // Generate a random state parameter for security and include user ID
    let state = encode_spotify_state(user.id, client_redirect_url.as_deref());
    
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
        urlencoding::encode(&state)
    );

    Ok(Json(ApiResponse::success(SpotifyAuthUrlResponse {
        auth_url,
        state,
    })))
}

pub async fn get_tidal_auth_url(
    State(_state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
    Query(query): Query<TidalAuthUrlQuery>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<SpotifyAuthUrlResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let client_id = std::env::var("TIDAL_CLIENT_ID").unwrap_or_default();
    let redirect_uri = resolve_tidal_redirect_uri(&headers);
    let client_unique_key = std::env::var("TIDAL_CLIENT_UNIQUE_KEY").unwrap_or_default();
    let scopes = normalize_tidal_scopes();
    let client_redirect_url = normalize_client_redirect_url(query.redirect_url).map_err(|error| {
        (StatusCode::BAD_REQUEST, Json(ApiResponse::<()>::error(error)))
    })?;

    if client_id.is_empty() {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error("Tidal client ID not configured".to_string())),
        ));
    }

    let code_verifier = format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    );
    let code_challenge = {
        use base64::Engine as _;
        use sha2::{Digest, Sha256};

        let digest = Sha256::digest(code_verifier.as_bytes());
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest)
    };
    let state = encode_tidal_state(user.id, &code_verifier, client_redirect_url.as_deref());

    let mut params = vec![
        ("response_type".to_string(), "code".to_string()),
        ("client_id".to_string(), client_id),
        ("redirect_uri".to_string(), redirect_uri),
        ("code_challenge".to_string(), code_challenge),
        ("code_challenge_method".to_string(), "S256".to_string()),
        ("state".to_string(), state.clone()),
    ];

    if !client_unique_key.is_empty() {
        params.push(("client_unique_key".to_string(), client_unique_key));
    }

    if !scopes.is_empty() {
        params.push(("scope".to_string(), scopes));
    }

    let auth_query = params
        .into_iter()
        .map(|(key, value)| format!("{}={}", key, urlencoding::encode(&value)))
        .collect::<Vec<_>>()
        .join("&");

    Ok(Json(ApiResponse::success(SpotifyAuthUrlResponse {
        auth_url: format!("https://login.tidal.com/authorize?{}", auth_query),
        state,
    })))
}

pub async fn spotify_callback(
    State(state): State<AppState>,
    Query(params): Query<SpotifyCallbackQuery>,
    headers: HeaderMap,
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

    let (user_id, client_redirect_url) = match decode_spotify_state(&state_param) {
        Ok(decoded_state) => decoded_state,
        Err(error_message) => {
            let error_html = if let Some(client_redirect_url) = state_param
                .splitn(3, ':')
                .nth(2)
                .and_then(|encoded_redirect_url| base64::decode(encoded_redirect_url).ok())
                .and_then(|decoded_bytes| String::from_utf8(decoded_bytes).ok())
                .and_then(|decoded_redirect_url| normalize_client_redirect_url(Some(decoded_redirect_url)).ok().flatten())
            {
                let target_url = build_spotify_app_redirect_url(&client_redirect_url, "error", &error_message);
                build_spotify_app_redirect_html(
                    &target_url,
                    "Spotify Connection Error",
                    &error_message,
                    "#ef4444",
                )
            } else {
                format!(r#"
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
        <h1>❌ Connection Error</h1>
        <p>{}</p>
        <button class="close-btn" onclick="window.close()">Close Window</button>
    </div>
</body>
</html>
                "#, error_message)
            };

            return Err((StatusCode::BAD_REQUEST, Html(error_html)));
        }
    };

    // Exchange authorization code for access token
    let redirect_uri = resolve_spotify_redirect_uri(&headers);

    match exchange_spotify_code(&code, &redirect_uri, state.db(), user_id).await {
        Ok(message) => {
            if let Some(client_redirect_url) = client_redirect_url {
                let target_url = build_spotify_app_redirect_url(&client_redirect_url, "success", &message);
                let html = build_spotify_app_redirect_html(
                    &target_url,
                    "Spotify Connected",
                    "Spotify is connected. Returning you to the app...",
                    "#1db954",
                );
                return Ok(axum::response::Html(html));
            }

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

pub async fn tidal_callback(
    State(state): State<AppState>,
    Query(params): Query<TidalCallbackQuery>,
    headers: HeaderMap,
) -> Result<Html<String>, (StatusCode, Html<String>)> {
    if let Some(error) = params.error {
        return Err((
            StatusCode::BAD_REQUEST,
            Html(tidal_error_page(
                "Tidal Authorization Error",
                &format!("Tidal authorization failed: {}", error),
                "#0f766e",
            )),
        ));
    }

    let code = params.code.ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Html(tidal_error_page(
                "Tidal Connection Error",
                "No authorization code was returned by Tidal.",
                "#ef4444",
            )),
        )
    })?;

    let state_param = params.state.ok_or_else(|| {
        (
            StatusCode::BAD_REQUEST,
            Html(tidal_error_page(
                "Tidal Connection Error",
                "No state parameter was returned by Tidal.",
                "#ef4444",
            )),
        )
    })?;

    let (user_id, code_verifier, client_redirect_url) = decode_tidal_state(&state_param).map_err(|error| {
        (
            StatusCode::BAD_REQUEST,
            Html(tidal_error_page("Tidal Connection Error", &error, "#ef4444")),
        )
    })?;

    let client_id = std::env::var("TIDAL_CLIENT_ID").unwrap_or_default();
    let client_secret = std::env::var("TIDAL_CLIENT_SECRET").unwrap_or_default();
    let client_unique_key = std::env::var("TIDAL_CLIENT_UNIQUE_KEY").unwrap_or_default();
    let scopes = normalize_tidal_scopes();
    let redirect_uri = resolve_tidal_redirect_uri(&headers);

    if client_id.is_empty() {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Html(tidal_error_page(
                "Tidal Configuration Error",
                "Tidal client ID is not configured on the backend.",
                "#ef4444",
            )),
        ));
    }

    let mut form = vec![
        ("client_id", client_id),
        ("code", code),
        ("code_verifier", code_verifier),
        ("grant_type", "authorization_code".to_string()),
        ("redirect_uri", redirect_uri),
    ];

    if !client_secret.is_empty() {
        form.push(("client_secret", client_secret));
    }

    if !client_unique_key.is_empty() {
        form.push(("client_unique_key", client_unique_key));
    }

    if !scopes.is_empty() {
        form.push(("scope", scopes));
    }

    let client = reqwest::Client::new();
    let response = client
        .post("https://auth.tidal.com/v1/oauth2/token")
        .form(&form)
        .send()
        .await
        .map_err(|error| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Html(tidal_error_page(
                    "Tidal Connection Error",
                    &format!("Failed to exchange Tidal authorization code: {}", error),
                    "#ef4444",
                )),
            )
        })?;

    if !response.status().is_success() {
        let error_text = response.text().await.unwrap_or_default();
        return Err((
            StatusCode::BAD_GATEWAY,
            Html(tidal_error_page(
                "Tidal Connection Error",
                &format!("Tidal token exchange failed: {}", error_text),
                "#ef4444",
            )),
        ));
    }

    let token_response: TidalTokenExchangeResponse = response.json().await.map_err(|error| {
        (
            StatusCode::BAD_GATEWAY,
            Html(tidal_error_page(
                "Tidal Connection Error",
                &format!("Failed to parse Tidal token response: {}", error),
                "#ef4444",
            )),
        )
    })?;

    let account_username = token_response.user_id.as_ref().and_then(|value| {
        value
            .as_str()
            .map(|text| text.to_string())
            .or_else(|| value.as_i64().map(|number| number.to_string()))
    });
    let expires_at = token_response
        .expires_in
        .map(|expires_in| (chrono::Utc::now() + chrono::Duration::seconds(expires_in)).naive_utc());

    let existing_service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user_id))
        .filter(StreamingServiceColumn::ServiceName.eq("tidal"))
        .one(state.db())
        .await
        .map_err(|error| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Html(tidal_error_page(
                    "Tidal Connection Error",
                    &format!("Database error: {}", error),
                    "#ef4444",
                )),
            )
        })?;

    match existing_service {
        Some(existing) => {
            let mut service: StreamingServiceActiveModel = existing.into();
            service.access_token = Set(Some(token_response.access_token.clone()));
            service.refresh_token = Set(token_response.refresh_token.clone());
            service.expires_at = Set(expires_at);
            service.account_username = Set(account_username.clone());
            service.is_active = Set(true);
            service.update(state.db()).await.map_err(|error| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Html(tidal_error_page(
                        "Tidal Connection Error",
                        &format!("Failed to update Tidal connection: {}", error),
                        "#ef4444",
                    )),
                )
            })?;
        }
        None => {
            let new_service = StreamingServiceActiveModel {
                user_id: Set(user_id),
                service_name: Set("tidal".to_string()),
                access_token: Set(Some(token_response.access_token.clone())),
                refresh_token: Set(token_response.refresh_token.clone()),
                expires_at: Set(expires_at),
                account_username: Set(account_username.clone()),
                is_active: Set(true),
                ..Default::default()
            };

            new_service.insert(state.db()).await.map_err(|error| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Html(tidal_error_page(
                        "Tidal Connection Error",
                        &format!("Failed to save Tidal connection: {}", error),
                        "#ef4444",
                    )),
                )
            })?;
        }
    }

    if let Some(app_redirect_url) = client_redirect_url {
        let target_url = build_tidal_app_redirect_url(
            &app_redirect_url,
            "success",
            "Tidal connected successfully.",
        );
        let html = build_tidal_app_redirect_html(
            &target_url,
            "Tidal Connected",
            "Tidal authorization succeeded. Returning to the app.",
            "#0f766e",
        );
        return Ok(Html(html));
    }

    Ok(Html(tidal_error_page(
        "Tidal Connected",
        "Tidal authorization completed successfully. You can close this window.",
        "#0f766e",
    )))
}

async fn exchange_spotify_code(
    code: &str,
    redirect_uri: &str,
    db: &sea_orm::DatabaseConnection,
    user_id: uuid::Uuid,
) -> Result<String, String> {
    let client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
    let client_secret = std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default();

    if client_id.is_empty() || client_secret.is_empty() {
        return Err("Spotify credentials not configured".to_string());
    }

    let client = reqwest::Client::new();
    let auth_header = base64::encode(format!("{}:{}", client_id, client_secret));

    let mut form = std::collections::HashMap::new();
    form.insert("grant_type", "authorization_code");
    form.insert("code", code);
    form.insert("redirect_uri", redirect_uri);

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
    let (access_token, _) = get_valid_spotify_tokens(user.id, state.db()).await.map_err(|error| {
        (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error(error)),
        )
    })?;

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
    let (access_token, _) = get_valid_spotify_tokens(user.id, state.db()).await.map_err(|error| {
        (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error(error)),
        )
    })?;

    Ok(Json(ApiResponse::success(access_token)))
}

#[derive(Serialize)]
pub struct TidalSdkCredentialsResponse {
    pub access_token: String,
    pub client_id: String,
    pub client_unique_key: Option<String>,
    pub requested_scopes: Vec<String>,
    pub granted_scopes: Vec<String>,
    pub user_id: Option<String>,
    pub expires_at: Option<String>,
}

pub async fn get_tidal_sdk_credentials(
    State(state): State<AppState>,
    Extension(user): Extension<UserResponseDto>,
) -> Result<Json<ApiResponse<TidalSdkCredentialsResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let client_id = std::env::var("TIDAL_CLIENT_ID").unwrap_or_default();
    if client_id.is_empty() {
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiResponse::<()>::error("Tidal client ID not configured".to_string())),
        ));
    }

    let (access_token, _) = get_valid_tidal_tokens(user.id, state.db()).await.map_err(|error| {
        (
            StatusCode::UNAUTHORIZED,
            Json(ApiResponse::<()>::error(error)),
        )
    })?;

    let service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user.id))
        .filter(StreamingServiceColumn::ServiceName.eq("tidal"))
        .filter(StreamingServiceColumn::IsActive.eq(true))
        .one(state.db())
        .await
        .map_err(|error| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error(format!("Database error: {}", error))),
            )
        })?
        .ok_or_else(|| {
            (
                StatusCode::UNAUTHORIZED,
                Json(ApiResponse::<()>::error(
                    "Tidal service not connected for this user. Please connect to Tidal first."
                        .to_string(),
                )),
            )
        })?;

    let scopes = normalize_tidal_scopes()
        .split_whitespace()
        .filter(|scope| !scope.is_empty())
        .map(|scope| scope.to_string())
        .collect::<Vec<_>>();
    let expires_at = service
        .expires_at
        .map(|timestamp| timestamp.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string());
    let client_unique_key = std::env::var("TIDAL_CLIENT_UNIQUE_KEY")
        .ok()
        .filter(|value| !value.trim().is_empty());

    Ok(Json(ApiResponse::success(TidalSdkCredentialsResponse {
        access_token,
        client_id,
        client_unique_key,
        requested_scopes: scopes.clone(),
        granted_scopes: scopes,
        user_id: service.account_username,
        expires_at,
    })))
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
    match request_spotify_token_refresh(&request.refresh_token).await {
        Ok(refreshed_tokens) => Ok(Json(ApiResponse {
            success: true,
            data: Some(RefreshSpotifyTokenResponse {
                access_token: refreshed_tokens.access_token,
                expires_in: refreshed_tokens.expires_in,
            }),
            message: Some("Spotify token refreshed successfully".to_string()),
        })),
        Err(_) => Ok(Json(ApiResponse {
            success: false,
            data: None,
            message: Some("Failed to refresh Spotify token".to_string()),
        })),
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
            name: "tidal".to_string(),
            display_name: "Tidal".to_string(),
            supports_full_tracks: false,
            requires_premium: true,
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

    let tidal_connected = match get_authenticated_streaming_service("tidal", user.id, state.db()).await {
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

    let tidal_service = StreamingServiceEntity::find()
        .filter(StreamingServiceColumn::UserId.eq(user.id))
        .filter(StreamingServiceColumn::ServiceName.eq("tidal"))
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
            name: "tidal".to_string(),
            display_name: "Tidal".to_string(),
            is_connected: tidal_connected,
            connected_at: tidal_service.as_ref().map(|s| s.created_at.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()),
            account_username: tidal_service.as_ref().and_then(|s| s.account_username.clone()),
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
    if service_name != "qobuz" && service_name != "spotify" && service_name != "tidal" {
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
        Ok(tracks) => Ok(Json(ApiResponse::success(normalize_streaming_tracks(tracks)))),
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

// Stream local cover images (both cached and direct files)
pub async fn stream_local_cover(
    axum::extract::Path(file_path_param): axum::extract::Path<String>,
    _headers: HeaderMap,
) -> Result<Response, StatusCode> {
    use tokio::fs;
    
    // Decode the file path (can include subdirectories)
    let decoded_path = urlencoding::decode(&file_path_param)
        .map_err(|_| StatusCode::BAD_REQUEST)?
        .into_owned();
    
    // Determine if this is a cached cover or a direct file
    let file_path = if decoded_path.starts_with("cached/") {
        // This is a cached cover from extracted audio file
        let cache_filename = decoded_path.strip_prefix("cached/").unwrap_or(&decoded_path);
        let cache_dir = std::env::current_dir()
            .unwrap_or_else(|_| std::path::PathBuf::from("."))
            .join("cache")
            .join("covers");
        cache_dir.join(cache_filename)
    } else {
        // This is a direct cover image file from the music directory
        let music_dir = std::env::current_dir()
            .unwrap_or_else(|_| std::path::PathBuf::from("."))
            .join("own_music");
        let file_path = music_dir.join(&decoded_path);
        
        // Security check: ensure the file is within the own_music directory
        if !file_path.starts_with(&music_dir) {
            return Err(StatusCode::FORBIDDEN);
        }
        
        file_path
    };
    
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
        "webp" => "image/webp",
        _ => return Err(StatusCode::UNSUPPORTED_MEDIA_TYPE),
    };
    
    // Read the entire image file
    let content = fs::read(&file_path).await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // Create response with proper headers
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(
            header::CACHE_CONTROL,
            format!("public, max-age={}", COVER_CACHE_TTL_SECONDS),
        )
        .header(header::CONTENT_LENGTH, content.len())
        .body(content.into())
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

#[derive(Deserialize)]
pub struct GetProviderCoverQuery {
    pub url: String,
}

pub async fn stream_provider_cover(
    Query(params): Query<GetProviderCoverQuery>,
) -> Result<Response, StatusCode> {
    let decoded_url = urlencoding::decode(&params.url)
        .map_err(|_| StatusCode::BAD_REQUEST)?
        .into_owned();

    let parsed = url::Url::parse(&decoded_url).map_err(|_| StatusCode::BAD_REQUEST)?;
    if !matches!(parsed.scheme(), "http" | "https") {
        return Err(StatusCode::BAD_REQUEST);
    }

    let (content, content_type) = fetch_cached_provider_cover(&decoded_url)
        .await
        .map_err(|error| {
            error!("Failed to load provider cover {}: {}", decoded_url, error);
            StatusCode::BAD_GATEWAY
        })?;

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(
            header::CACHE_CONTROL,
            format!("public, max-age={}", COVER_CACHE_TTL_SECONDS),
        )
        .header(header::CONTENT_LENGTH, content.len())
        .body(content.into())
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}
