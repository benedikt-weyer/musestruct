use anyhow::{Result, anyhow};
use async_trait::async_trait;
use reqwest::Client;
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;

use super::{
    AuthResult, SearchResults, ServiceCredentials, StreamingAlbum, StreamingPlaylist,
    StreamingService, StreamingTrack,
};

pub struct TidalService {
    client: Client,
    client_id: String,
    client_secret: String,
    access_token: Option<String>,
    refresh_token: Option<String>,
}

impl TidalService {
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

    fn country_code(&self) -> String {
        std::env::var("TIDAL_COUNTRY_CODE")
            .ok()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "US".to_string())
    }

    async fn get_client_credentials_token(&self) -> Result<String> {
        if self.client_id.is_empty() || self.client_secret.is_empty() {
            return Err(anyhow!("Tidal credentials not configured"));
        }

        let form = [
            ("client_id", self.client_id.as_str()),
            ("client_secret", self.client_secret.as_str()),
            ("grant_type", "client_credentials"),
        ];

        let response = self
            .client
            .post("https://auth.tidal.com/v1/oauth2/token")
            .form(&form)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("Tidal token error: {}", error_text));
        }

        let token_response: TidalTokenResponse = response.json().await?;
        Ok(token_response.access_token)
    }

    async fn make_request(&self, endpoint: &str, params: &HashMap<String, String>) -> Result<Value> {
        self.make_request_pairs(
            endpoint,
            &params
                .iter()
                .map(|(key, value)| (key.as_str(), value.as_str()))
                .collect::<Vec<_>>(),
        )
        .await
    }

    async fn make_request_pairs(&self, endpoint: &str, params: &[(&str, &str)]) -> Result<Value> {
        let token = if let Some(token) = &self.access_token {
            token.clone()
        } else {
            self.get_client_credentials_token().await?
        };

        let mut request = self
            .client
            .get(format!("https://openapi.tidal.com/v2/{}", endpoint))
            .header("Authorization", format!("Bearer {}", token))
            .header("Accept", "application/vnd.api+json");

        if !params.is_empty() {
            request = request.query(params);
        }

        let response = request.send().await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow!("Tidal API error: {}", error_text));
        }

        Ok(response.json::<Value>().await?)
    }

    fn playback_formats(quality: Option<&str>) -> Vec<&'static str> {
        match quality.unwrap_or_default().to_ascii_lowercase().as_str() {
            "low" | "lossy" | "he-aac" => vec!["HEAACV1", "AACLC"],
            _ => vec!["AACLC", "HEAACV1"],
        }
    }

    async fn get_track_file_relationship(&self, track_id: &str) -> Result<Option<(String, String)>> {
        let response = self
            .make_request_pairs(
                &format!("tracks/{}/relationships/sourceFile", track_id),
                &[("include", "sourceFile")],
            )
            .await?;

        let Some(data) = response.get("data") else {
            return Ok(None);
        };

        let Some(id) = data.get("id").and_then(Value::as_str) else {
            return Ok(None);
        };
        let resource_type = data
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();

        if resource_type.is_empty() {
            return Ok(None);
        }

        Ok(Some((id.to_string(), resource_type)))
    }

    async fn get_track_file_url(&self, track_file_id: &str, quality: Option<&str>) -> Result<Option<String>> {
        let formats = Self::playback_formats(quality);
        let mut params = vec![("usage", "PLAYBACK")];
        for format in &formats {
            params.push(("formats", *format));
        }

        let response = self
            .make_request_pairs(&format!("trackFiles/{}", track_file_id), &params)
            .await?;

        Ok(response
            .get("data")
            .and_then(|data| data.get("attributes"))
            .and_then(|attributes| attributes.get("url"))
            .and_then(Value::as_str)
            .map(|value| value.to_string()))
    }

    async fn get_track_manifest_url(&self, track_id: &str, quality: Option<&str>) -> Result<String> {
        let formats = Self::playback_formats(quality);
        let mut params = vec![
            ("manifestType", "HLS"),
            ("uriScheme", "HTTPS"),
            ("usage", "PLAYBACK"),
            ("adaptive", "true"),
        ];
        for format in &formats {
            params.push(("formats", *format));
        }

        let response = self
            .make_request_pairs(&format!("trackManifests/{}", track_id), &params)
            .await?;
        let attributes = response
            .get("data")
            .and_then(|data| data.get("attributes"))
            .ok_or_else(|| anyhow!("Tidal did not return playback metadata for this track"))?;

        if attributes.get("drmData").is_some() {
            return Err(anyhow!("Tidal returned DRM-protected playback that the current player cannot handle"));
        }

        attributes
            .get("uri")
            .and_then(Value::as_str)
            .map(|value| value.to_string())
            .ok_or_else(|| anyhow!("Tidal did not return a playable manifest URL"))
    }

    fn parse_duration(duration: Option<&str>) -> Option<i32> {
        let mut total_seconds = 0i32;
        let mut current_number = String::new();
        let mut in_time = false;

        for character in duration?.chars() {
            match character {
                'P' => continue,
                'T' => in_time = true,
                'H' if in_time => {
                    total_seconds += current_number.parse::<i32>().ok()? * 3600;
                    current_number.clear();
                }
                'M' if in_time => {
                    total_seconds += current_number.parse::<i32>().ok()? * 60;
                    current_number.clear();
                }
                'S' if in_time => {
                    total_seconds += current_number.parse::<i32>().ok()?;
                    current_number.clear();
                }
                value if value.is_ascii_digit() => current_number.push(value),
                _ => {}
            }
        }

        Some(total_seconds)
    }

    fn attr_string(resource: &JsonApiResource, key: &str) -> Option<String> {
        resource
            .attributes
            .as_ref()
            .and_then(|attributes| attributes.get(key))
            .and_then(Value::as_str)
            .map(|value| value.to_string())
    }

    fn attr_bool(resource: &JsonApiResource, key: &str) -> Option<bool> {
        resource
            .attributes
            .as_ref()
            .and_then(|attributes| attributes.get(key))
            .and_then(Value::as_bool)
    }

    fn attr_u32(resource: &JsonApiResource, key: &str) -> Option<u32> {
        resource
            .attributes
            .as_ref()
            .and_then(|attributes| attributes.get(key))
            .and_then(Value::as_u64)
            .and_then(|value| u32::try_from(value).ok())
    }

    fn external_url(resource: &JsonApiResource) -> Option<String> {
        let links = resource
            .attributes
            .as_ref()
            .and_then(|attributes| attributes.get("externalLinks"))
            .and_then(Value::as_array)?;

        links.iter().find_map(|link| {
            ["href", "url", "uri"]
                .iter()
                .find_map(|key| link.get(key).and_then(Value::as_str))
                .map(|value| value.to_string())
        })
    }

    fn relationship_ids(resource: &JsonApiResource, relationship_name: &str) -> Vec<String> {
        let Some(relationships) = &resource.relationships else {
            return Vec::new();
        };
        let Some(relationship) = relationships.get(relationship_name) else {
            return Vec::new();
        };
        let Some(data) = &relationship.data else {
            return Vec::new();
        };

        match data {
            Value::Array(items) => items
                .iter()
                .filter_map(|item| item.get("id").and_then(Value::as_str).map(|value| value.to_string()))
                .collect(),
            Value::Object(item) => item
                .get("id")
                .and_then(Value::as_str)
                .map(|value| vec![value.to_string()])
                .unwrap_or_default(),
            _ => Vec::new(),
        }
    }

    fn resource_map(document: &JsonApiDocument) -> HashMap<String, JsonApiResource> {
        let mut resources = HashMap::new();

        if let Some(data) = &document.data {
            match data {
                Value::Object(_) => {
                    if let Ok(resource) = serde_json::from_value::<JsonApiResource>(data.clone()) {
                        resources.insert(format!("{}:{}", resource.resource_type, resource.id), resource);
                    }
                }
                Value::Array(items) => {
                    for item in items {
                        if let Ok(resource) = serde_json::from_value::<JsonApiResource>(item.clone()) {
                            resources.insert(format!("{}:{}", resource.resource_type, resource.id), resource);
                        }
                    }
                }
                _ => {}
            }
        }

        if let Some(included) = &document.included {
            for resource in included {
                resources.insert(format!("{}:{}", resource.resource_type, resource.id), resource.clone());
            }
        }

        resources
    }

    fn resource_values(document: &JsonApiDocument, resource_type: &str) -> Vec<JsonApiResource> {
        Self::resource_map(document)
            .into_values()
            .filter(|resource| resource.resource_type == resource_type)
            .collect()
    }

    fn first_related_name(
        resource: &JsonApiResource,
        relationship_name: &str,
        related_type: &str,
        resources: &HashMap<String, JsonApiResource>,
        attribute_name: &str,
        default_value: &str,
    ) -> String {
        Self::relationship_ids(resource, relationship_name)
            .into_iter()
            .find_map(|related_id| {
                resources
                    .get(&format!("{}:{}", related_type, related_id))
                    .and_then(|related_resource| Self::attr_string(related_resource, attribute_name))
            })
            .unwrap_or_else(|| default_value.to_string())
    }

    fn parse_track_resource(
        resource: &JsonApiResource,
        resources: &HashMap<String, JsonApiResource>,
    ) -> StreamingTrack {
        StreamingTrack {
            id: resource.id.clone(),
            title: Self::attr_string(resource, "title").unwrap_or_else(|| "Unknown Track".to_string()),
            artist: Self::first_related_name(resource, "artists", "artists", resources, "name", "Unknown Artist"),
            album: Self::first_related_name(resource, "albums", "albums", resources, "title", "Unknown Album"),
            duration: Self::parse_duration(Self::attr_string(resource, "duration").as_deref()),
            stream_url: None,
            cover_url: None,
            quality: None,
            source: "tidal".to_string(),
            bitrate: None,
            sample_rate: None,
            bit_depth: None,
        }
    }

    fn parse_album_resource(
        resource: &JsonApiResource,
        resources: &HashMap<String, JsonApiResource>,
    ) -> StreamingAlbum {
        StreamingAlbum {
            id: resource.id.clone(),
            title: Self::attr_string(resource, "title").unwrap_or_else(|| "Unknown Album".to_string()),
            artist: Self::first_related_name(resource, "artists", "artists", resources, "name", "Unknown Artist"),
            release_date: Self::attr_string(resource, "releaseDate"),
            cover_url: None,
            tracks: vec![],
            source: "tidal".to_string(),
        }
    }

    fn parse_playlist_resource(
        resource: &JsonApiResource,
        resources: &HashMap<String, JsonApiResource>,
    ) -> StreamingPlaylist {
        let owner = {
            let owner_profile = Self::first_related_name(
                resource,
                "ownerProfiles",
                "profiles",
                resources,
                "name",
                "",
            );

            if owner_profile.is_empty() {
                let owner_artist = Self::first_related_name(
                    resource,
                    "owners",
                    "artists",
                    resources,
                    "name",
                    "Unknown",
                );

                if owner_artist.is_empty() {
                    "Unknown".to_string()
                } else {
                    owner_artist
                }
            } else {
                owner_profile
            }
        };

        StreamingPlaylist {
            id: resource.id.clone(),
            name: Self::attr_string(resource, "name").unwrap_or_else(|| "Unknown Playlist".to_string()),
            description: Self::attr_string(resource, "description"),
            owner,
            source: "tidal".to_string(),
            cover_url: None,
            track_count: Self::attr_u32(resource, "numberOfItems").unwrap_or(0),
            is_public: matches!(Self::attr_string(resource, "accessType").as_deref(), Some("PUBLIC")),
            external_url: Self::external_url(resource),
        }
    }

    async fn search_document(&self, query: &str) -> Result<JsonApiDocument> {
        let mut params = HashMap::new();
        params.insert("countryCode".to_string(), self.country_code());
        params.insert("include".to_string(), "tracks,albums,playlists,artists,ownerProfiles,profiles".to_string());

        let response = self
            .make_request(&format!("searchResults/{}", urlencoding::encode(query)), &params)
            .await?;
        Ok(serde_json::from_value(response)?)
    }

    async fn collection_document(&self, endpoint: &str) -> Result<JsonApiDocument> {
        let mut params = HashMap::new();
        params.insert("countryCode".to_string(), self.country_code());
        params.insert("include".to_string(), "items".to_string());

        let response = self.make_request(endpoint, &params).await?;
        Ok(serde_json::from_value(response)?)
    }
}

#[async_trait]
impl StreamingService for TidalService {
    async fn search(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        let document = self.search_document(query).await?;
        let resources = Self::resource_map(&document);
        let offset = offset.unwrap_or(0) as usize;
        let limit = limit.unwrap_or(20) as usize;

        let mut tracks = Self::resource_values(&document, "tracks")
            .into_iter()
            .map(|resource| Self::parse_track_resource(&resource, &resources))
            .collect::<Vec<_>>();
        let mut albums = Self::resource_values(&document, "albums")
            .into_iter()
            .map(|resource| Self::parse_album_resource(&resource, &resources))
            .collect::<Vec<_>>();

        let total = tracks.len().max(albums.len()) as u32;
        tracks = tracks.into_iter().skip(offset).take(limit).collect();
        albums = albums.into_iter().skip(offset).take(limit).collect();

        Ok(SearchResults {
            tracks,
            albums,
            playlists: vec![],
            total,
            offset: offset as u32,
            limit: limit as u32,
        })
    }

    async fn search_playlists(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<StreamingPlaylist>> {
        let document = self.search_document(query).await?;
        let resources = Self::resource_map(&document);
        let offset = offset.unwrap_or(0) as usize;
        let limit = limit.unwrap_or(20) as usize;

        Ok(Self::resource_values(&document, "playlists")
            .into_iter()
            .map(|resource| Self::parse_playlist_resource(&resource, &resources))
            .skip(offset)
            .take(limit)
            .collect())
    }

    async fn search_library(&self, query: &str, search_type: Option<&str>, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        let offset = offset.unwrap_or(0) as usize;
        let limit = limit.unwrap_or(20) as usize;

        match search_type.unwrap_or("track") {
            "album" => {
                let document = self.collection_document("userCollectionAlbums/me/relationships/items").await?;
                let resources = Self::resource_map(&document);
                let albums = Self::resource_values(&document, "albums")
                    .into_iter()
                    .map(|resource| Self::parse_album_resource(&resource, &resources))
                    .filter(|album| {
                        let normalized_query = query.to_lowercase();
                        album.title.to_lowercase().contains(&normalized_query)
                            || album.artist.to_lowercase().contains(&normalized_query)
                    })
                    .skip(offset)
                    .take(limit)
                    .collect::<Vec<_>>();
                let total = albums.len() as u32;
                Ok(SearchResults {
                    tracks: vec![],
                    albums,
                    playlists: vec![],
                    total,
                    offset: offset as u32,
                    limit: limit as u32,
                })
            }
            "playlist" => {
                let document = self.collection_document("userCollectionPlaylists/me/relationships/items").await?;
                let resources = Self::resource_map(&document);
                let playlists = Self::resource_values(&document, "playlists")
                    .into_iter()
                    .map(|resource| Self::parse_playlist_resource(&resource, &resources))
                    .filter(|playlist| playlist.name.to_lowercase().contains(&query.to_lowercase()))
                    .skip(offset)
                    .take(limit)
                    .collect::<Vec<_>>();
                let total = playlists.len() as u32;
                Ok(SearchResults {
                    tracks: vec![],
                    albums: vec![],
                    playlists,
                    total,
                    offset: offset as u32,
                    limit: limit as u32,
                })
            }
            _ => {
                let document = self.collection_document("userCollectionTracks/me/relationships/items").await?;
                let resources = Self::resource_map(&document);
                let tracks = Self::resource_values(&document, "tracks")
                    .into_iter()
                    .map(|resource| Self::parse_track_resource(&resource, &resources))
                    .filter(|track| {
                        let normalized_query = query.to_lowercase();
                        track.title.to_lowercase().contains(&normalized_query)
                            || track.artist.to_lowercase().contains(&normalized_query)
                            || track.album.to_lowercase().contains(&normalized_query)
                    })
                    .skip(offset)
                    .take(limit)
                    .collect::<Vec<_>>();
                let total = tracks.len() as u32;
                Ok(SearchResults {
                    tracks,
                    albums: vec![],
                    playlists: vec![],
                    total,
                    offset: offset as u32,
                    limit: limit as u32,
                })
            }
        }
    }

    async fn get_playlist_tracks(&self, playlist_id: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<StreamingTrack>> {
        let document = self.collection_document(&format!("playlists/{}/relationships/items", playlist_id)).await?;
        let resources = Self::resource_map(&document);
        let offset = offset.unwrap_or(0) as usize;
        let limit = limit.unwrap_or(50) as usize;

        Ok(Self::resource_values(&document, "tracks")
            .into_iter()
            .map(|resource| Self::parse_track_resource(&resource, &resources))
            .skip(offset)
            .take(limit)
            .collect())
    }

    async fn get_album_tracks(&self, album_id: &str) -> Result<Vec<StreamingTrack>> {
        let document = self.collection_document(&format!("albums/{}/relationships/items", album_id)).await?;
        let resources = Self::resource_map(&document);

        Ok(Self::resource_values(&document, "tracks")
            .into_iter()
            .map(|resource| Self::parse_track_resource(&resource, &resources))
            .collect())
    }

    async fn get_stream_url(&self, track_id: &str, quality: Option<&str>) -> Result<String> {
        if let Some((track_file_id, resource_type)) = self.get_track_file_relationship(track_id).await? {
            if resource_type == "trackFiles" {
                if let Some(url) = self.get_track_file_url(&track_file_id, quality).await? {
                    return Ok(url);
                }
            }
        }

        self.get_track_manifest_url(track_id, quality).await
    }

    async fn get_track(&self, track_id: &str) -> Result<StreamingTrack> {
        let mut params = HashMap::new();
        params.insert("countryCode".to_string(), self.country_code());
        params.insert("include".to_string(), "albums,artists".to_string());
        let response = self.make_request(&format!("tracks/{}", track_id), &params).await?;
        let document: JsonApiDocument = serde_json::from_value(response)?;
        let resources = Self::resource_map(&document);
        let resource = resources
            .get(&format!("tracks:{}", track_id))
            .ok_or_else(|| anyhow!("Track not found"))?;
        Ok(Self::parse_track_resource(resource, &resources))
    }

    async fn authenticate(&self, credentials: &ServiceCredentials) -> Result<AuthResult> {
        if let Some(access_token) = &credentials.access_token {
            Ok(AuthResult {
                access_token: Some(access_token.clone()),
                refresh_token: credentials.refresh_token.clone(),
                expires_at: Some(chrono::Utc::now() + chrono::Duration::hours(1)),
                user_id: None,
            })
        } else {
            Err(anyhow!("Tidal requires OAuth tokens. Please use the web authentication flow."))
        }
    }

    async fn is_authenticated(&self) -> bool {
        self.access_token.is_some()
    }

    fn service_name(&self) -> &str {
        "tidal"
    }
}

#[derive(Clone, Debug, Deserialize)]
struct JsonApiDocument {
    data: Option<Value>,
    included: Option<Vec<JsonApiResource>>,
}

#[derive(Clone, Debug, Deserialize)]
struct JsonApiResource {
    id: String,
    #[serde(rename = "type")]
    resource_type: String,
    attributes: Option<Value>,
    relationships: Option<HashMap<String, JsonApiRelationship>>,
}

#[derive(Clone, Debug, Deserialize)]
struct JsonApiRelationship {
    data: Option<Value>,
}

#[derive(Debug, Deserialize)]
struct TidalTokenResponse {
    access_token: String,
}
