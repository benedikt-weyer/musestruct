use async_trait::async_trait;
use anyhow::{Result, anyhow};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use super::{StreamingService, SearchResults, StreamingTrack, StreamingAlbum, ServiceCredentials, AuthResult};

pub struct SpotifyService {
    client: Client,
    client_id: String,
    client_secret: String,
    access_token: Option<String>,
    refresh_token: Option<String>,
}

impl SpotifyService {
    pub fn new(client_id: String, client_secret: String) -> Self {
        Self {
            client: Client::new(),
            client_id,
            client_secret,
            access_token: None,
            refresh_token: None,
        }
    }

    pub fn with_tokens(mut self, access_token: String, refresh_token: Option<String>) -> Self {
        self.access_token = Some(access_token);
        self.refresh_token = refresh_token;
        self
    }

    async fn get_client_credentials_token(&self) -> Result<String> {
        let auth_header = base64::encode(format!("{}:{}", self.client_id, self.client_secret));
        
        let mut form = HashMap::new();
        form.insert("grant_type", "client_credentials");

        let response = self.client
            .post("https://accounts.spotify.com/api/token")
            .header("Authorization", format!("Basic {}", auth_header))
            .form(&form)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("Spotify token error: {}", error_text));
        }

        let token_response: SpotifyTokenResponse = response.json().await?;
        Ok(token_response.access_token)
    }

    async fn make_request<T: for<'de> Deserialize<'de>>(&self, endpoint: &str, params: &HashMap<String, String>) -> Result<T> {
        let token = if let Some(token) = &self.access_token {
            token.clone()
        } else {
            self.get_client_credentials_token().await?
        };

        let mut url = format!("https://api.spotify.com/v1/{}", endpoint);
        if !params.is_empty() {
            let query_string: Vec<String> = params.iter()
                .map(|(k, v)| format!("{}={}", urlencoding::encode(k), urlencoding::encode(v)))
                .collect();
            url.push('?');
            url.push_str(&query_string.join("&"));
        }

        let response = self.client
            .get(&url)
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("Spotify API error: {}", error_text));
        }

        let result = response.json::<T>().await?;
        Ok(result)
    }
}

#[async_trait]
impl StreamingService for SpotifyService {
    async fn search(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        let mut params = HashMap::new();
        params.insert("q".to_string(), query.to_string());
        params.insert("type".to_string(), "track,album".to_string());
        params.insert("limit".to_string(), limit.unwrap_or(20).to_string());
        params.insert("offset".to_string(), offset.unwrap_or(0).to_string());

        let response: SpotifySearchResponse = self.make_request("search", &params).await?;

        let tracks = response.tracks.items.into_iter().map(|track| {
            let album_name = track.album.name;
            let artist_name = if let Some(artist) = track.artists.first() {
                artist.name.clone()
            } else {
                "Unknown Artist".to_string()
            };
            let cover_url = track.album.images.first().map(|img| img.url.clone());

            StreamingTrack {
                id: track.id,
                title: track.name,
                artist: artist_name,
                album: album_name,
                duration: Some((track.duration_ms / 1000) as i32), // Convert to seconds
                stream_url: track.preview_url, // Spotify only provides 30-second previews
                cover_url,
                quality: Some("preview".to_string()), // Spotify Web API only provides previews
                source: "spotify".to_string(),
                bitrate: Some(160), // Spotify previews are typically 160kbps
                sample_rate: Some(44100), // Standard CD sample rate
                bit_depth: None, // Not specified for MP3 previews
            }
        }).collect();

        let albums = response.albums.items.into_iter().map(|album| {
            let artist_name = if let Some(artist) = album.artists.first() {
                artist.name.clone()
            } else {
                "Unknown Artist".to_string()
            };
            let cover_url = album.images.first().map(|img| img.url.clone());

            StreamingAlbum {
                id: album.id,
                title: album.name,
                artist: artist_name,
                release_date: Some(album.release_date),
                cover_url,
                tracks: vec![], // Would need separate API call to get tracks
            }
        }).collect();

        Ok(SearchResults {
            tracks,
            albums,
            total: response.tracks.total,
            offset: response.tracks.offset,
            limit: response.tracks.limit,
        })
    }

    async fn get_stream_url(&self, track_id: &str, _quality: Option<&str>) -> Result<String> {
        // Get track details to fetch preview URL
        let track: SpotifyTrack = self.make_request(&format!("tracks/{}", track_id), &HashMap::new()).await?;
        
        track.preview_url.ok_or_else(|| anyhow!("No preview URL available for this track"))
    }

    async fn get_track(&self, track_id: &str) -> Result<StreamingTrack> {
        let track: SpotifyTrack = self.make_request(&format!("tracks/{}", track_id), &HashMap::new()).await?;

        let artist_name = if let Some(artist) = track.artists.first() {
            artist.name.clone()
        } else {
            "Unknown Artist".to_string()
        };
        let cover_url = track.album.images.first().map(|img| img.url.clone());

        Ok(StreamingTrack {
            id: track.id,
            title: track.name,
            artist: artist_name,
            album: track.album.name,
            duration: Some((track.duration_ms / 1000) as i32),
            stream_url: track.preview_url,
            cover_url,
            quality: Some("preview".to_string()),
            source: "spotify".to_string(),
            bitrate: Some(160), // Spotify previews are typically 160kbps
            sample_rate: Some(44100), // Standard CD sample rate
            bit_depth: None, // Not specified for MP3 previews
        })
    }

    async fn authenticate(&self, credentials: &ServiceCredentials) -> Result<AuthResult> {
        // Spotify uses OAuth2 flow, this would typically be handled in a web flow
        // For this implementation, we assume tokens are provided
        if let (Some(access_token), refresh_token) = (&credentials.access_token, &credentials.refresh_token) {
            Ok(AuthResult {
                access_token: Some(access_token.clone()),
                refresh_token: refresh_token.clone(),
                expires_at: Some(chrono::Utc::now() + chrono::Duration::hours(1)), // Spotify tokens expire in 1 hour
                user_id: None, // Would need to call /me endpoint to get user ID
            })
        } else {
            Err(anyhow!("Spotify requires OAuth2 tokens. Please use the web authentication flow."))
        }
    }

    async fn is_authenticated(&self) -> bool {
        self.access_token.is_some()
    }

    fn service_name(&self) -> &str {
        "spotify"
    }
}

// Spotify API response structures
#[derive(Debug, Deserialize)]
struct SpotifySearchResponse {
    tracks: SpotifyTrackSearchResult,
    albums: SpotifyAlbumSearchResult,
}

#[derive(Debug, Deserialize)]
struct SpotifyTrackSearchResult {
    items: Vec<SpotifyTrack>,
    total: u32,
    limit: u32,
    offset: u32,
}

#[derive(Debug, Deserialize)]
struct SpotifyAlbumSearchResult {
    items: Vec<SpotifyAlbum>,
    total: u32,
    limit: u32,
    offset: u32,
}

#[derive(Debug, Deserialize)]
struct SpotifyTrack {
    id: String,
    name: String,
    artists: Vec<SpotifyArtist>,
    album: SpotifyAlbum,
    duration_ms: u32,
    preview_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SpotifyAlbum {
    id: String,
    name: String,
    artists: Vec<SpotifyArtist>,
    release_date: String,
    images: Vec<SpotifyImage>,
}

#[derive(Debug, Deserialize)]
struct SpotifyArtist {
    id: String,
    name: String,
}

#[derive(Debug, Deserialize)]
struct SpotifyImage {
    url: String,
    height: Option<u32>,
    width: Option<u32>,
}

#[derive(Debug, Deserialize)]
struct SpotifyTokenResponse {
    access_token: String,
    token_type: String,
    expires_in: u32,
}

