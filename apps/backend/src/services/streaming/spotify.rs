use async_trait::async_trait;
use anyhow::{Result, anyhow};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use super::{StreamingAlbum, StreamingPlaylist, StreamingService, SearchResults, StreamingTrack, ServiceCredentials, AuthResult};

const SPOTIFY_LIBRARY_PAGE_SIZE: u32 = 50;
const SPOTIFY_LIBRARY_MAX_ITEMS: u32 = 500;

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

    fn matches_query(fields: &[&str], query: &str) -> bool {
        let normalized_query = query.trim().to_lowercase();

        if normalized_query.is_empty() {
            return true;
        }

        fields
            .iter()
            .any(|field| field.to_lowercase().contains(&normalized_query))
    }

    fn paginate_results<T>(items: Vec<T>, limit: u32, offset: u32) -> (Vec<T>, u32) {
        let total = items.len() as u32;
        let paginated_items = items
            .into_iter()
            .skip(offset as usize)
            .take(limit as usize)
            .collect();

        (paginated_items, total)
    }

    async fn get_saved_tracks(&self) -> Result<Vec<StreamingTrack>> {
        let mut saved_tracks = Vec::new();
        let mut offset = 0;

        loop {
            let mut params = HashMap::new();
            params.insert("limit".to_string(), SPOTIFY_LIBRARY_PAGE_SIZE.to_string());
            params.insert("offset".to_string(), offset.to_string());

            let response: SpotifySavedTracksResponse = self.make_request("me/tracks", &params).await?;

            if response.items.is_empty() {
                break;
            }

            let page_count = response.items.len() as u32;
            saved_tracks.extend(response.items.into_iter().map(|item| {
                let track = item.track;
                let artist_name = track
                    .artists
                    .first()
                    .map(|artist| artist.name.clone())
                    .unwrap_or_else(|| "Unknown Artist".to_string());
                let cover_url = track.album.images.first().map(|image| image.url.clone());

                StreamingTrack {
                    id: track.id,
                    title: track.name,
                    artist: artist_name,
                    album: track.album.name,
                    duration: Some((track.duration_ms / 1000) as i32),
                    stream_url: track.preview_url,
                    cover_url,
                    quality: Some("preview".to_string()),
                    source: "spotify".to_string(),
                    bitrate: Some(160),
                    sample_rate: Some(44100),
                    bit_depth: None,
                }
            }));

            offset += page_count;
            if offset >= response.total || offset >= SPOTIFY_LIBRARY_MAX_ITEMS {
                break;
            }
        }

        Ok(saved_tracks)
    }

    async fn get_saved_albums(&self) -> Result<Vec<StreamingAlbum>> {
        let mut saved_albums = Vec::new();
        let mut offset = 0;

        loop {
            let mut params = HashMap::new();
            params.insert("limit".to_string(), SPOTIFY_LIBRARY_PAGE_SIZE.to_string());
            params.insert("offset".to_string(), offset.to_string());

            let response: SpotifySavedAlbumsResponse = self.make_request("me/albums", &params).await?;

            if response.items.is_empty() {
                break;
            }

            let page_count = response.items.len() as u32;
            saved_albums.extend(response.items.into_iter().map(|item| {
                let album = item.album;
                let artist_name = album
                    .artists
                    .first()
                    .map(|artist| artist.name.clone())
                    .unwrap_or_else(|| "Unknown Artist".to_string());
                let cover_url = album.images.first().map(|image| image.url.clone());

                StreamingAlbum {
                    id: album.id,
                    title: album.name,
                    artist: artist_name,
                    release_date: Some(album.release_date),
                    cover_url,
                    tracks: vec![],
                    source: "spotify".to_string(),
                }
            }));

            offset += page_count;
            if offset >= response.total || offset >= SPOTIFY_LIBRARY_MAX_ITEMS {
                break;
            }
        }

        Ok(saved_albums)
    }

    async fn get_saved_playlists(&self) -> Result<Vec<StreamingPlaylist>> {
        let mut saved_playlists = Vec::new();
        let mut offset = 0;

        loop {
            let mut params = HashMap::new();
            params.insert("limit".to_string(), SPOTIFY_LIBRARY_PAGE_SIZE.to_string());
            params.insert("offset".to_string(), offset.to_string());

            let response: SpotifyCurrentUserPlaylistsResponse = self.make_request("me/playlists", &params).await?;

            if response.items.is_empty() {
                break;
            }

            let page_count = response.items.len() as u32;
            saved_playlists.extend(response.items.into_iter().map(|playlist| StreamingPlaylist {
                id: playlist.id,
                name: playlist.name,
                description: playlist.description,
                owner: playlist.owner.display_name.unwrap_or_else(|| "Unknown".to_string()),
                source: "spotify".to_string(),
                cover_url: playlist.images.first().map(|image| image.url.clone()),
                track_count: playlist.tracks.total,
                is_public: playlist.public,
                external_url: Some(playlist.external_urls.spotify),
            }));

            offset += page_count;
            if offset >= response.total || offset >= SPOTIFY_LIBRARY_MAX_ITEMS {
                break;
            }
        }

        Ok(saved_playlists)
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
                source: "spotify".to_string(),
            }
        }).collect();

        Ok(SearchResults {
            tracks,
            albums,
            playlists: vec![], // Will be populated by search_playlists method
            total: response.tracks.total,
            offset: response.tracks.offset,
            limit: response.tracks.limit,
        })
    }

    async fn search_playlists(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<super::StreamingPlaylist>> {
        let mut params = HashMap::new();
        params.insert("q".to_string(), query.to_string());
        params.insert("type".to_string(), "playlist".to_string());
        params.insert("limit".to_string(), limit.unwrap_or(20).to_string());
        params.insert("offset".to_string(), offset.unwrap_or(0).to_string());

        let response: SpotifyPlaylistSearchResponse = self.make_request("search", &params).await?;

        let playlists = response.playlists.items.into_iter().map(|playlist| {
            super::StreamingPlaylist {
                id: playlist.id,
                name: playlist.name,
                description: playlist.description,
                owner: playlist.owner.display_name.unwrap_or_else(|| "Unknown".to_string()),
                source: "spotify".to_string(),
                cover_url: playlist.images.first().map(|img| img.url.clone()),
                track_count: playlist.tracks.total,
                is_public: playlist.public,
                external_url: Some(playlist.external_urls.spotify),
            }
        }).collect();

        Ok(playlists)
    }

    async fn get_playlist_tracks(&self, playlist_id: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<super::StreamingTrack>> {
        let mut params = HashMap::new();
        params.insert("limit".to_string(), limit.unwrap_or(50).to_string());
        params.insert("offset".to_string(), offset.unwrap_or(0).to_string());

        let response: SpotifyPlaylistTracksResponse = self.make_request(&format!("playlists/{}/tracks", playlist_id), &params).await?;

        let tracks = response.items.into_iter()
            .filter_map(|item| item.track)
            .map(|track| {
                super::StreamingTrack {
                    id: track.id,
                    title: track.name,
                    artist: track.artists.first().map(|a| a.name.clone()).unwrap_or_else(|| "Unknown Artist".to_string()),
                    album: track.album.name,
                    duration: Some((track.duration_ms / 1000) as i32), // Convert to seconds
                    stream_url: None, // Will be fetched when needed
                    cover_url: track.album.images.first().map(|img| img.url.clone()),
                    quality: Some("320kbps".to_string()),
                    source: "spotify".to_string(),
                    bitrate: Some(320),
                    sample_rate: Some(44100),
                    bit_depth: Some(16),
                }
            })
            .collect();

        Ok(tracks)
    }

    async fn get_album_tracks(&self, album_id: &str) -> Result<Vec<super::StreamingTrack>> {
        let mut params = HashMap::new();
        params.insert("limit".to_string(), "50".to_string());

        let response: SpotifyAlbumTracksResponse = self.make_request(&format!("albums/{}/tracks", album_id), &params).await?;

        let tracks = response.items.into_iter()
            .map(|track| {
                let artist_name = if let Some(artist) = track.artists.first() {
                    artist.name.clone()
                } else {
                    "Unknown Artist".to_string()
                };

                super::StreamingTrack {
                    id: track.id,
                    title: track.name,
                    artist: artist_name,
                    album: "Unknown Album".to_string(), // We don't have album info in track response
                    duration: Some((track.duration_ms / 1000) as i32),
                    stream_url: track.preview_url,
                    cover_url: None, // Not available in album tracks response
                    quality: Some("preview".to_string()),
                    source: "spotify".to_string(),
                    bitrate: Some(160), // Spotify previews are typically 160kbps
                    sample_rate: Some(44100), // Standard CD sample rate
                    bit_depth: None, // Not specified for MP3 previews
                }
            })
            .collect();

        Ok(tracks)
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

    async fn search_library(&self, query: &str, search_type: Option<&str>, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        let limit = limit.unwrap_or(20);
        let offset = offset.unwrap_or(0);

        match search_type.unwrap_or("track") {
            "album" => {
                let matching_albums = self
                    .get_saved_albums()
                    .await?
                    .into_iter()
                    .filter(|album| Self::matches_query(&[&album.title, &album.artist], query))
                    .collect::<Vec<_>>();
                let (albums, total) = Self::paginate_results(matching_albums, limit, offset);

                Ok(SearchResults {
                    tracks: vec![],
                    albums,
                    playlists: vec![],
                    total,
                    offset,
                    limit,
                })
            }
            "playlist" => {
                let matching_playlists = self
                    .get_saved_playlists()
                    .await?
                    .into_iter()
                    .filter(|playlist| {
                        Self::matches_query(
                            &[
                                &playlist.name,
                                playlist.description.as_deref().unwrap_or(""),
                                &playlist.owner,
                            ],
                            query,
                        )
                    })
                    .collect::<Vec<_>>();
                let (playlists, total) = Self::paginate_results(matching_playlists, limit, offset);

                Ok(SearchResults {
                    tracks: vec![],
                    albums: vec![],
                    playlists,
                    total,
                    offset,
                    limit,
                })
            }
            _ => {
                let matching_tracks = self
                    .get_saved_tracks()
                    .await?
                    .into_iter()
                    .filter(|track| Self::matches_query(&[&track.title, &track.artist, &track.album], query))
                    .collect::<Vec<_>>();
                let (tracks, total) = Self::paginate_results(matching_tracks, limit, offset);

                Ok(SearchResults {
                    tracks,
                    albums: vec![],
                    playlists: vec![],
                    total,
                    offset,
                    limit,
                })
            }
        }
    }
}

// Spotify API response structures
#[derive(Debug, Deserialize)]
struct SpotifySearchResponse {
    tracks: SpotifyTrackSearchResult,
    albums: SpotifyAlbumSearchResult,
}

#[derive(Debug, Deserialize)]
struct SpotifyPlaylistSearchResponse {
    playlists: SpotifyPlaylistSearchResult,
}

#[derive(Debug, Deserialize)]
struct SpotifyPlaylistSearchResult {
    items: Vec<SpotifyPlaylist>,
    total: u32,
    limit: u32,
    offset: u32,
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
struct SpotifySavedTracksResponse {
    items: Vec<SpotifySavedTrackItem>,
    total: u32,
}

#[derive(Debug, Deserialize)]
struct SpotifySavedTrackItem {
    track: SpotifyTrack,
}

#[derive(Debug, Deserialize)]
struct SpotifySavedAlbumsResponse {
    items: Vec<SpotifySavedAlbumItem>,
    total: u32,
}

#[derive(Debug, Deserialize)]
struct SpotifySavedAlbumItem {
    album: SpotifyAlbum,
}

#[derive(Debug, Deserialize)]
struct SpotifyCurrentUserPlaylistsResponse {
    items: Vec<SpotifyPlaylist>,
    total: u32,
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
struct SpotifyPlaylist {
    id: String,
    name: String,
    description: Option<String>,
    owner: SpotifyPlaylistOwner,
    public: bool,
    images: Vec<SpotifyImage>,
    tracks: SpotifyPlaylistTracks,
    external_urls: SpotifyExternalUrls,
}

#[derive(Debug, Deserialize)]
struct SpotifyPlaylistOwner {
    display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SpotifyPlaylistTracksResponse {
    items: Vec<SpotifyPlaylistTrackItem>,
    total: u32,
    limit: u32,
    offset: u32,
}

#[derive(Debug, Deserialize)]
struct SpotifyPlaylistTrackItem {
    track: Option<SpotifyTrack>,
}

#[derive(Debug, Deserialize)]
struct SpotifyAlbumTracksResponse {
    items: Vec<SpotifySimpleTrack>,
    total: u32,
    limit: u32,
    offset: u32,
}

#[derive(Debug, Deserialize)]
struct SpotifySimpleTrack {
    id: String,
    name: String,
    artists: Vec<SpotifyArtist>,
    duration_ms: u32,
    preview_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SpotifyPlaylistTracks {
    total: u32,
}

#[derive(Debug, Deserialize)]
struct SpotifyExternalUrls {
    spotify: String,
}

#[derive(Debug, Deserialize)]
struct SpotifyTokenResponse {
    access_token: String,
    token_type: String,
    expires_in: u32,
}

