use async_trait::async_trait;
use anyhow::{Result, anyhow};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing;
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

    async fn make_request<T: for<'de> Deserialize<'de>>(&self, endpoint: &str, params: &HashMap<String, String>) -> Result<T> {
        let mut url_params = params.clone();
        url_params.insert("app_id".to_string(), self.app_id.clone());

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
        params.insert("limit".to_string(), limit.unwrap_or(20).to_string());
        params.insert("offset".to_string(), offset.unwrap_or(0).to_string());

        let response: QobuzSearchResponse = self.make_request("catalog/search", &params).await?;

        let tracks = response.tracks.items.into_iter().map(|track| StreamingTrack {
            id: Self::json_value_to_string(&track.id),
            title: track.title,
            artist: track.performer.as_ref().map(|p| p.name.clone()).unwrap_or_else(|| "Unknown Artist".to_string()),
            album: track.album.as_ref().map(|a| a.title.clone()).unwrap_or_else(|| "Unknown Album".to_string()),
            duration: track.duration,
            stream_url: None, // Will be fetched when needed
            cover_url: track.album.as_ref().and_then(|a| a.image.as_ref().and_then(|i| i.large.clone())),
            quality: Some("lossless".to_string()),
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
            total: response.tracks.total,
            offset: response.tracks.offset,
            limit: response.tracks.limit,
        })
    }

    async fn get_stream_url(&self, track_id: &str, quality: Option<&str>) -> Result<String> {
        let mut params = HashMap::new();
        params.insert("track_id".to_string(), track_id.to_string());
        params.insert("format_id".to_string(), "27".to_string()); // Hi-Res quality
        
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

        Ok(StreamingTrack {
            id: Self::json_value_to_string(&track.id),
            title: track.title,
            artist: track.performer.as_ref().map(|p| p.name.clone()).unwrap_or_else(|| "Unknown Artist".to_string()),
            album: track.album.as_ref().map(|a| a.title.clone()).unwrap_or_else(|| "Unknown Album".to_string()),
            duration: track.duration,
            stream_url: None,
            cover_url: track.album.as_ref().and_then(|a| a.image.as_ref().and_then(|i| i.large.clone())),
            quality: Some("lossless".to_string()),
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
