use anyhow::{Result, anyhow};
use reqwest::header::CONTENT_TYPE;
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};
use tokio::fs;
use url::Url;

use crate::services::streaming::{SearchResults, StreamingAlbum, StreamingPlaylist, StreamingTrack};

pub const COVER_CACHE_TTL_SECONDS: u64 = 60 * 60 * 24 * 365;
const PROVIDER_COVER_ROUTE: &str = "/api/stream/cover/provider";

struct CachedCoverEntry {
    path: PathBuf,
    content_type: String,
    modified_at: SystemTime,
}

pub fn cache_cover_url(cover_url: Option<String>) -> Option<String> {
    cover_url.and_then(|value| cache_cover_url_ref(&value))
}

pub fn cache_cover_url_ref(cover_url: &str) -> Option<String> {
    let trimmed = cover_url.trim();
    if trimmed.is_empty() {
        return None;
    }

    if is_remote_cover_url(trimmed) {
        return Some(format!(
            "{PROVIDER_COVER_ROUTE}?url={}",
            urlencoding::encode(trimmed)
        ));
    }

    Some(trimmed.to_string())
}

pub fn normalize_streaming_track(mut track: StreamingTrack) -> StreamingTrack {
    track.cover_url = cache_cover_url(track.cover_url);
    track
}

pub fn normalize_streaming_tracks(tracks: Vec<StreamingTrack>) -> Vec<StreamingTrack> {
    tracks.into_iter().map(normalize_streaming_track).collect()
}

pub fn normalize_streaming_album(mut album: StreamingAlbum) -> StreamingAlbum {
    album.cover_url = cache_cover_url(album.cover_url);
    album.tracks = normalize_streaming_tracks(album.tracks);
    album
}

pub fn normalize_streaming_playlist(mut playlist: StreamingPlaylist) -> StreamingPlaylist {
    playlist.cover_url = cache_cover_url(playlist.cover_url);
    playlist
}

pub fn normalize_search_results(mut results: SearchResults) -> SearchResults {
    results.tracks = normalize_streaming_tracks(results.tracks);
    results.albums = results
        .albums
        .into_iter()
        .map(normalize_streaming_album)
        .collect();
    results.playlists = results
        .playlists
        .into_iter()
        .map(normalize_streaming_playlist)
        .collect();
    results
}

pub async fn fetch_cached_provider_cover(remote_url: &str) -> Result<(Vec<u8>, String)> {
    let cache_dir = provider_cover_cache_dir();
    fs::create_dir_all(&cache_dir).await?;

    let cache_key = cache_key_for_url(remote_url);
    let existing_entry = find_cached_cover_entry(&cache_dir, &cache_key).await?;

    if let Some(entry) = existing_entry.as_ref() {
        if is_cache_entry_fresh(entry) {
            return read_cached_cover_entry(entry).await;
        }
    }

    match fetch_remote_cover(remote_url).await {
        Ok((content, extension, content_type)) => {
            remove_cached_cover_entries(&cache_dir, &cache_key).await?;

            let cache_path = cache_dir.join(format!("{}.{}", cache_key, extension));
            fs::write(cache_path, &content).await?;

            Ok((content, content_type))
        }
        Err(error) => {
            if let Some(entry) = existing_entry.as_ref() {
                return read_cached_cover_entry(entry).await;
            }

            Err(error)
        }
    }
}

fn provider_cover_cache_dir() -> PathBuf {
    std::env::current_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join("cache")
        .join("provider_covers")
}

fn cache_key_for_url(remote_url: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(remote_url.as_bytes());
    format!("{:x}", hasher.finalize())
}

fn is_cache_entry_fresh(entry: &CachedCoverEntry) -> bool {
    entry
        .modified_at
        .elapsed()
        .map(|elapsed| elapsed <= Duration::from_secs(COVER_CACHE_TTL_SECONDS))
        .unwrap_or(false)
}

fn is_remote_cover_url(cover_url: &str) -> bool {
    if is_internal_cover_url(cover_url) {
        return false;
    }

    match Url::parse(cover_url) {
        Ok(parsed) => matches!(parsed.scheme(), "http" | "https"),
        Err(_) => false,
    }
}

fn is_internal_cover_url(cover_url: &str) -> bool {
    if cover_url.starts_with("/api/stream/local/cover/") || cover_url.starts_with(PROVIDER_COVER_ROUTE)
    {
        return true;
    }

    match Url::parse(cover_url) {
        Ok(parsed) => {
            parsed.path().starts_with("/api/stream/local/cover/")
                || parsed.path().starts_with(PROVIDER_COVER_ROUTE)
        }
        Err(_) => false,
    }
}

async fn find_cached_cover_entry(cache_dir: &Path, cache_key: &str) -> Result<Option<CachedCoverEntry>> {
    let mut entries = match fs::read_dir(cache_dir).await {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        let stem = path.file_stem().and_then(|value| value.to_str());
        if stem != Some(cache_key) {
            continue;
        }

        let extension = match path.extension().and_then(|value| value.to_str()) {
            Some(extension) => extension,
            None => continue,
        };

        let Some(content_type) = content_type_from_extension(extension) else {
            continue;
        };

        let metadata = entry.metadata().await?;
        let modified_at = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);

        return Ok(Some(CachedCoverEntry {
            path,
            content_type: content_type.to_string(),
            modified_at,
        }));
    }

    Ok(None)
}

async fn read_cached_cover_entry(entry: &CachedCoverEntry) -> Result<(Vec<u8>, String)> {
    let content = fs::read(&entry.path).await?;
    Ok((content, entry.content_type.clone()))
}

async fn remove_cached_cover_entries(cache_dir: &Path, cache_key: &str) -> Result<()> {
    let mut entries = match fs::read_dir(cache_dir).await {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        let stem = path.file_stem().and_then(|value| value.to_str());
        if stem == Some(cache_key) {
            let _ = fs::remove_file(path).await;
        }
    }

    Ok(())
}

async fn fetch_remote_cover(remote_url: &str) -> Result<(Vec<u8>, &'static str, String)> {
    let response = reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()?
        .get(remote_url)
        .send()
        .await?;

    if !response.status().is_success() {
        return Err(anyhow!(
            "Failed to fetch provider cover with status {}",
            response.status()
        ));
    }

    let response_content_type = response
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.split(';').next().unwrap_or("").trim().to_lowercase())
        .unwrap_or_default();

    if !response_content_type.is_empty() && !response_content_type.starts_with("image/") {
        return Err(anyhow!(
            "Provider cover did not return an image content type: {}",
            response_content_type
        ));
    }

    let extension = extension_from_content_type(&response_content_type)
        .or_else(|| extension_from_remote_url(remote_url))
        .ok_or_else(|| anyhow!("Unsupported provider cover format"))?;

    let content = response.bytes().await?.to_vec();
    if content.is_empty() {
        return Err(anyhow!("Provider cover response was empty"));
    }

    let content_type = content_type_from_extension(extension)
        .ok_or_else(|| anyhow!("Unsupported provider cover extension: {}", extension))?
        .to_string();

    Ok((content, extension, content_type))
}

fn extension_from_content_type(content_type: &str) -> Option<&'static str> {
    match content_type {
        "image/jpeg" => Some("jpg"),
        "image/png" => Some("png"),
        "image/gif" => Some("gif"),
        "image/bmp" => Some("bmp"),
        "image/webp" => Some("webp"),
        _ => None,
    }
}

fn extension_from_remote_url(remote_url: &str) -> Option<&'static str> {
    let parsed = Url::parse(remote_url).ok()?;
    let path = Path::new(parsed.path());
    let extension = path.extension()?.to_str()?;
    normalize_extension(extension)
}

fn content_type_from_extension(extension: &str) -> Option<&'static str> {
    match normalize_extension(extension)? {
        "jpg" => Some("image/jpeg"),
        "png" => Some("image/png"),
        "gif" => Some("image/gif"),
        "bmp" => Some("image/bmp"),
        "webp" => Some("image/webp"),
        _ => None,
    }
}

fn normalize_extension(extension: &str) -> Option<&'static str> {
    match extension.trim().to_lowercase().as_str() {
        "jpg" | "jpeg" => Some("jpg"),
        "png" => Some("png"),
        "gif" => Some("gif"),
        "bmp" => Some("bmp"),
        "webp" => Some("webp"),
        _ => None,
    }
}