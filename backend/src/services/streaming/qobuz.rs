use async_trait::async_trait;
use anyhow::{Result, anyhow};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use tracing;
use md5;
use super::{StreamingService, SearchResults, StreamingTrack, StreamingAlbum, ServiceCredentials, AuthResult};

pub struct QobuzService {
    client: Client,
    app_id: String,
    secret: String,
    user_auth_token: Option<String>,
}

impl QobuzService {
    pub fn new(app_id: String, secret: String) -> Self {
        Self {
            client: Client::new(),
            app_id,
            secret,
            user_auth_token: None,
        }
    }

    pub fn with_auth_token(mut self, token: String) -> Self {
        self.user_auth_token = Some(token);
        self
    }

    fn json_value_to_string(value: &serde_json::Value) -> String {
        match value {
            serde_json::Value::String(s) => s.clone(),
            serde_json::Value::Number(n) => n.to_string(),
            _ => value.to_string(),
        }
    }

    fn generate_request_signature(&self, endpoint: &str, params: &HashMap<String, String>, timestamp: &str) -> String {
        // Different endpoints require different signature formats
        let sig_string = match endpoint {
            "track/getFileUrl" => {
                let default_empty = String::new();
                let default_stream = "stream".to_string();
                let track_id = params.get("track_id").unwrap_or(&default_empty);
                let format_id = params.get("format_id").unwrap_or(&default_empty);
                let intent = params.get("intent").unwrap_or(&default_stream);
                format!("trackgetFileUrlformat_id{}intent{}track_id{}{}{}", format_id, intent, track_id, timestamp, self.secret)
            },
            _ => {
                // For other endpoints, use a generic signature format
                let mut sorted_params: Vec<_> = params.iter().collect();
                sorted_params.sort_by_key(|&(k, _)| k);
                let params_string: String = sorted_params.iter()
                    .map(|(k, v)| format!("{}{}", k, v))
                    .collect();
                format!("{}{}{}", endpoint.replace("/", ""), params_string, self.secret)
            }
        };
        
        format!("{:x}", md5::compute(sig_string.as_bytes()))
    }

    async fn make_request<T: for<'de> Deserialize<'de>>(&self, endpoint: &str, params: &HashMap<String, String>) -> Result<T> {
        let mut url_params = params.clone();
        url_params.insert("app_id".to_string(), self.app_id.clone());

        // Add request timestamp - required for some endpoints like getFileUrl
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| anyhow!("Failed to get current time: {}", e))?
            .as_secs();
        let timestamp_str = timestamp.to_string();
        url_params.insert("request_ts".to_string(), timestamp_str.clone());

        // Generate and add request signature for secure endpoints
        if endpoint == "track/getFileUrl" {
            let signature = self.generate_request_signature(endpoint, &url_params, &timestamp_str);
            url_params.insert("request_sig".to_string(), signature);
        }

        if let Some(token) = &self.user_auth_token {
            url_params.insert("user_auth_token".to_string(), token.clone());
        }

        let response = self.client
            .get(&format!("https://www.qobuz.com/api.json/0.2/{}", endpoint))
            .query(&url_params)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("Qobuz API error: {}", error_text));
        }

        // Get the response text first for debugging
        let response_text = response.text().await?;
        
        // Try to parse the JSON
        match serde_json::from_str::<T>(&response_text) {
            Ok(result) => Ok(result),
            Err(e) => {
                // Log the actual response for debugging
                tracing::error!("Failed to parse Qobuz response: {}", e);
                tracing::error!("Raw response: {}", response_text);
                Err(anyhow!("Failed to parse Qobuz response: {}. Raw response: {}", e, response_text))
            }
        }
    }
}

#[async_trait]
impl StreamingService for QobuzService {
    async fn search(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        let mut params = HashMap::new();
        params.insert("query".to_string(), query.to_string());
        // Don't set type parameter for general search - Qobuz searches all types when no type is specified
        params.insert("limit".to_string(), limit.unwrap_or(20).to_string());
        params.insert("offset".to_string(), offset.unwrap_or(0).to_string());

        let response: QobuzSearchResponse = self.make_request("catalog/search", &params).await?;

        let tracks = response.tracks.items.into_iter().map(|track| {
            // Qobuz typically provides high-quality audio
            let (bitrate, sample_rate, bit_depth) = if self.user_auth_token.is_some() {
                // Authenticated users get access to Hi-Res quality
                (Some(1411), Some(44100), Some(16)) // CD quality as baseline, Hi-Res can be up to 24bit/192kHz
            } else {
                // Non-authenticated users get MP3 quality
                (Some(320), None, None)
            };

            StreamingTrack {
                id: Self::json_value_to_string(&track.id),
                title: track.title,
                artist: track.performer.as_ref().map(|p| p.name.clone()).unwrap_or_else(|| "Unknown Artist".to_string()),
                album: track.album.as_ref().map(|a| a.title.clone()).unwrap_or_else(|| "Unknown Album".to_string()),
                duration: track.duration,
                stream_url: None, // Will be fetched when needed
                cover_url: track.album.as_ref().and_then(|a| a.image.as_ref().and_then(|i| i.large.clone())),
                quality: Some("lossless".to_string()),
                source: "qobuz".to_string(),
                bitrate,
                sample_rate,
                bit_depth,
            }
        }).collect();

        let albums = response.albums.items.into_iter().map(|album| StreamingAlbum {
            id: Self::json_value_to_string(&album.id),
            title: album.title,
            artist: album.artist.as_ref().map(|a| a.name.clone()).unwrap_or_else(|| "Unknown Artist".to_string()),
            release_date: album.released_at.map(|d| d.to_string()),
            cover_url: album.image.as_ref().and_then(|i| i.large.clone()),
            tracks: vec![], // Tracks would be fetched separately
        }).collect();

        Ok(SearchResults {
            tracks,
            albums,
            playlists: vec![], // Qobuz doesn't have playlists in search results
            total: response.tracks.total,
            offset: response.tracks.offset,
            limit: response.tracks.limit,
        })
    }

    async fn search_playlists(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<super::StreamingPlaylist>> {
        let mut params = HashMap::new();
        params.insert("query".to_string(), query.to_string());
        params.insert("type".to_string(), "playlists".to_string());
        params.insert("limit".to_string(), limit.unwrap_or(20).to_string());
        params.insert("offset".to_string(), offset.unwrap_or(0).to_string());

        let response: QobuzCatalogSearchResponse = self.make_request("catalog/search", &params).await?;

        let playlists = response.playlists.items.into_iter().map(|playlist| {
            super::StreamingPlaylist {
                id: Self::json_value_to_string(&playlist.id),
                name: playlist.name,
                description: playlist.description,
                owner: playlist.creator.as_ref().map(|c| c.name.clone()).unwrap_or_else(|| "Unknown".to_string()),
                source: "qobuz".to_string(),
                cover_url: playlist.image.as_ref().and_then(|i| i.large.clone()),
                track_count: playlist.tracks_count.unwrap_or(0),
                is_public: playlist.is_public.unwrap_or(false),
                external_url: playlist.url,
            }
        }).collect();

        Ok(playlists)
    }

    async fn get_playlist_tracks(&self, playlist_id: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<super::StreamingTrack>> {
        let mut params = HashMap::new();
        params.insert("playlist_id".to_string(), playlist_id.to_string());
        params.insert("extra".to_string(), "tracks".to_string());
        params.insert("limit".to_string(), limit.unwrap_or(100).to_string());
        params.insert("offset".to_string(), offset.unwrap_or(0).to_string());

        let response: QobuzPlaylistTracksResponse = self.make_request("playlist/get", &params).await?;

        let tracks = response.tracks.items.into_iter().enumerate().filter_map(|(index, track)| {
            // Skip tracks without valid ID (similar to Python code)
            if track.id.is_null() {
                return None;
            }

            // Qobuz typically provides high-quality audio
            let (bitrate, sample_rate, bit_depth) = if self.user_auth_token.is_some() {
                // Authenticated users get access to Hi-Res quality
                (Some(1411), Some(44100), Some(16)) // CD quality as baseline, Hi-Res can be up to 24bit/192kHz
            } else {
                // Non-authenticated users get MP3 quality
                (Some(320), None, None)
            };

            Some(super::StreamingTrack {
                id: Self::json_value_to_string(&track.id),
                title: track.title,
                artist: track.performer.as_ref().map(|p| p.name.clone()).unwrap_or_else(|| "Unknown Artist".to_string()),
                album: track.album.as_ref().map(|a| a.title.clone()).unwrap_or_else(|| "Unknown Album".to_string()),
                duration: track.duration,
                stream_url: None, // Will be fetched when needed
                cover_url: track.album.as_ref().and_then(|a| a.image.as_ref().and_then(|i| i.large.clone())),
                quality: Some("lossless".to_string()),
                source: "qobuz".to_string(),
                bitrate,
                sample_rate,
                bit_depth,
                // Note: Position tracking would need to be added to StreamingTrack struct if needed
            })
        }).collect();

        Ok(tracks)
    }

    async fn get_stream_url(&self, track_id: &str, quality: Option<&str>) -> Result<String> {
        let mut params = HashMap::new();
        params.insert("track_id".to_string(), track_id.to_string());
        params.insert("format_id".to_string(), "27".to_string()); // Hi-Res quality
        params.insert("intent".to_string(), "stream".to_string()); // Required for signature
        
        // Use lower quality if not authenticated or requested
        if self.user_auth_token.is_none() || quality == Some("lossy") {
            params.insert("format_id".to_string(), "5".to_string()); // MP3 320kbps
        }

        let response: QobuzStreamResponse = self.make_request("track/getFileUrl", &params).await?;
        Ok(response.url)
    }

    async fn get_track(&self, track_id: &str) -> Result<StreamingTrack> {
        let mut params = HashMap::new();
        params.insert("track_id".to_string(), track_id.to_string());

        let track: QobuzTrack = self.make_request("track/get", &params).await?;

        // Determine audio quality based on authentication status
        let (bitrate, sample_rate, bit_depth) = if self.user_auth_token.is_some() {
            // Authenticated users get access to Hi-Res quality
            (Some(1411), Some(44100), Some(16)) // CD quality as baseline, Hi-Res can be up to 24bit/192kHz
        } else {
            // Non-authenticated users get MP3 quality
            (Some(320), None, None)
        };

        Ok(StreamingTrack {
            id: Self::json_value_to_string(&track.id),
            title: track.title,
            artist: track.performer.as_ref().map(|p| p.name.clone()).unwrap_or_else(|| "Unknown Artist".to_string()),
            album: track.album.as_ref().map(|a| a.title.clone()).unwrap_or_else(|| "Unknown Album".to_string()),
            duration: track.duration,
            stream_url: None,
            cover_url: track.album.as_ref().and_then(|a| a.image.as_ref().and_then(|i| i.large.clone())),
            quality: Some("lossless".to_string()),
            source: "qobuz".to_string(),
            bitrate,
            sample_rate,
            bit_depth,
        })
    }

    async fn authenticate(&self, credentials: &ServiceCredentials) -> Result<AuthResult> {
        let username = credentials.username.as_ref().ok_or_else(|| anyhow!("Username required for Qobuz"))?;
        let password = credentials.password.as_ref().ok_or_else(|| anyhow!("Password required for Qobuz"))?;

        let mut params = HashMap::new();
        params.insert("username".to_string(), username.clone());
        params.insert("password".to_string(), password.clone());
        params.insert("app_id".to_string(), self.app_id.clone());

        let response: QobuzAuthResponse = self.make_request("user/login", &params).await?;

        Ok(AuthResult {
            access_token: Some(response.user_auth_token),
            refresh_token: None,
            expires_at: None, // Qobuz tokens don't expire
            user_id: Some(Self::json_value_to_string(&response.user.id)),
        })
    }

    async fn is_authenticated(&self) -> bool {
        self.user_auth_token.is_some()
    }

    fn service_name(&self) -> &str {
        "qobuz"
    }
}

// Qobuz API response structures
#[derive(Debug, Deserialize)]
struct QobuzSearchResponse {
    tracks: QobuzTrackList,
    albums: QobuzAlbumList,
}

#[derive(Debug, Deserialize)]
struct QobuzTrackList {
    items: Vec<QobuzTrack>,
    total: u32,
    limit: u32,
    offset: u32,
}

#[derive(Debug, Deserialize)]
struct QobuzAlbumList {
    items: Vec<QobuzAlbum>,
    total: u32,
    limit: u32,
    offset: u32,
}

#[derive(Debug, Deserialize)]
struct QobuzTrack {
    id: serde_json::Value, // Can be string or number
    title: String,
    duration: Option<i32>,
    performer: Option<QobuzArtist>,
    album: Option<QobuzAlbum>,
}

#[derive(Debug, Deserialize)]
struct QobuzAlbum {
    id: serde_json::Value, // Can be string or number
    title: String,
    artist: Option<QobuzArtist>,
    released_at: Option<i64>, // Can be negative (dates before 1970)
    image: Option<QobuzImage>,
}

#[derive(Debug, Deserialize)]
struct QobuzArtist {
    id: serde_json::Value, // Can be string or number
    name: String,
}

#[derive(Debug, Deserialize)]
struct QobuzImage {
    large: Option<String>,
    small: Option<String>,
}

#[derive(Debug, Deserialize)]
struct QobuzStreamResponse {
    url: String,
}

#[derive(Debug, Deserialize)]
struct QobuzAuthResponse {
    user_auth_token: String,
    user: QobuzUser,
}

#[derive(Debug, Deserialize)]
struct QobuzUser {
    id: serde_json::Value, // Can be string or number
    login: String,
}

#[derive(Debug, Deserialize)]
struct QobuzCatalogSearchResponse {
    playlists: QobuzPlaylistList,
}

#[derive(Debug, Deserialize)]
struct QobuzPlaylistList {
    items: Vec<QobuzPlaylist>,
    total: u32,
    limit: u32,
    offset: u32,
}

#[derive(Debug, Deserialize)]
struct QobuzPlaylist {
    id: serde_json::Value, // Can be string or number
    name: String,
    description: Option<String>,
    creator: Option<QobuzPlaylistCreator>,
    image: Option<QobuzImage>,
    tracks_count: Option<u32>,
    is_public: Option<bool>,
    url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct QobuzPlaylistCreator {
    name: String,
}

#[derive(Debug, Deserialize)]
struct QobuzPlaylistTracksResponse {
    tracks: QobuzPlaylistTracksList,
}

#[derive(Debug, Deserialize)]
struct QobuzPlaylistTracksList {
    items: Vec<QobuzTrack>,
    total: u32,
    limit: u32,
    offset: u32,
}
