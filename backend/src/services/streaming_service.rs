use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::fs;
use tokio::io::AsyncWriteExt;
use tokio::sync::RwLock;
use uuid::Uuid;
use axum::{
    extract::Path as AxumPath,
    http::{header, StatusCode, HeaderMap},
    response::Response,
    routing::get,
    Router,
};
use tokio::io::AsyncReadExt;
use crate::handlers::auth::AppState;
use serde::Deserialize;

#[derive(Debug, Clone)]
pub struct CachedTrack {
    pub id: String,
    pub file_path: PathBuf,
    pub duration: u64,
    pub size: u64,
    pub cached_at: SystemTime,
    pub source: String,
}

#[derive(Debug, Deserialize)]
pub struct StreamQuery {
    pub track_id: String,
    pub source: String,
    pub url: String,
}

pub struct StreamingService {
    cache_dir: PathBuf,
    cached_tracks: Arc<RwLock<HashMap<String, CachedTrack>>>,
    max_cache_size: u64, // in bytes
    max_age: Duration,
}

impl StreamingService {
    pub fn new(cache_dir: PathBuf) -> Self {
        Self {
            cache_dir,
            cached_tracks: Arc::new(RwLock::new(HashMap::new())),
            max_cache_size: 5 * 1024 * 1024 * 1024, // 5GB
            max_age: Duration::from_secs(24 * 60 * 60), // 24 hours
        }
    }

    pub async fn initialize(&self) -> anyhow::Result<()> {
        // Create cache directory if it doesn't exist
        fs::create_dir_all(&self.cache_dir).await?;
        
        // Clean up old cached files on startup
        self.cleanup_old_cache().await?;
        
        Ok(())
    }

    pub async fn get_stream_url(&self, track_id: &str, source: &str, original_url: &str, title: Option<&str>, artist: Option<&str>) -> anyhow::Result<String> {
        // Create deterministic cache key based on source, artist, and title
        let cache_key = if let (Some(title), Some(artist)) = (title, artist) {
            // Normalize the strings for consistent hashing (only trim, no lowercase)
            let normalized_title = title.trim();
            let normalized_artist = artist.trim();
            use sha2::{Sha256, Digest};
            
            // Create input string for hashing
            let input = format!("{}|{}|{}", source, normalized_artist, normalized_title);
            let mut hasher = Sha256::new();
            hasher.update(input.as_bytes());
            let hash = hasher.finalize();
            let hash_hex = format!("{:x}", hash);
            
            hash_hex
        } else {
            // Fallback to original behavior if metadata is missing
            format!("{}_{}", source, track_id)
        };
        
        println!("Getting stream URL for track_id: {}, source: {}, title: {:?}, artist: {:?}, cache_key: {}", 
                track_id, source, title, artist, cache_key);
        
        // Check if track is already cached
        {
            let cached_tracks = self.cached_tracks.read().await;
            if let Some(cached_track) = cached_tracks.get(&cache_key) {
                println!("Found existing cached track: {:?}", cached_track);
                if self.is_track_valid(cached_track).await {
                    println!("Cached track is valid, returning URL: /api/stream/{}", cached_track.id);
                    return Ok(format!("/api/stream/{}", cached_track.id));
                } else {
                    println!("Cached track is invalid, will re-download");
                }
            } else {
                println!("No cached track found for key: {}", cache_key);
            }
        }

        // Download and cache the track
        println!("Downloading and caching track...");
        let cached_track = self.download_and_cache_track(track_id, source, original_url, &cache_key).await?;
        
        // Store in memory cache
        {
            let mut cached_tracks = self.cached_tracks.write().await;
            cached_tracks.insert(cache_key.clone(), cached_track.clone());
            println!("Stored track in cache with key: {}", cache_key);
        }

        let stream_url = format!("/api/stream/{}", cached_track.id);
        println!("Returning stream URL: {}", stream_url);
        Ok(stream_url)
    }

    async fn download_and_cache_track(
        &self,
        track_id: &str,
        source: &str,
        original_url: &str,
        cache_key: &str,
    ) -> anyhow::Result<CachedTrack> {
        // Use deterministic cache ID based on the cache key
        let cache_id = cache_key.replace("/", "_").replace("\\", "_"); // Sanitize for filename
        let file_path = self.cache_dir.join(format!("{}.mp3", cache_id));
        
        println!("Downloading track {} from {} to {}", track_id, source, file_path.display());
        
        // Download the track
        let response = reqwest::get(original_url).await?;
        let content_length = response.content_length().unwrap_or(0);
        
        if content_length > self.max_cache_size {
            return Err(anyhow::anyhow!("Track too large for caching"));
        }

        let mut file = fs::File::create(&file_path).await?;
        let mut stream = response.bytes_stream();
        
        let mut total_size = 0;
        use futures_util::StreamExt;
        
        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            total_size += chunk.len() as u64;
            
            if total_size > self.max_cache_size {
                // Clean up partial file
                let _ = fs::remove_file(&file_path).await;
                return Err(anyhow::anyhow!("Track too large for caching"));
            }
            
            file.write_all(&chunk).await?;
        }
        
        file.flush().await?;
        
        // Get file metadata
        let metadata = fs::metadata(&file_path).await?;
        let duration = self.estimate_duration(&file_path).await.unwrap_or(0);
        
        let cached_track = CachedTrack {
            id: cache_id,
            file_path,
            duration,
            size: metadata.len(),
            cached_at: SystemTime::now(),
            source: source.to_string(),
        };
        
        println!("Successfully cached track {} ({} bytes)", track_id, total_size);
        Ok(cached_track)
    }

    async fn estimate_duration(&self, _file_path: &Path) -> anyhow::Result<u64> {
        // For now, return 0. In a real implementation, you'd use a library like ffprobe
        // or mp3 metadata reader to get the actual duration
        Ok(0)
    }

    async fn is_track_valid(&self, cached_track: &CachedTrack) -> bool {
        // Check if file still exists
        if !cached_track.file_path.exists() {
            return false;
        }
        
        // Check if file is not too old
        let now = SystemTime::now();
        if let Ok(age) = now.duration_since(cached_track.cached_at) {
            if age > self.max_age {
                return false;
            }
        }
        
        true
    }

    async fn cleanup_old_cache(&self) -> anyhow::Result<()> {
        let mut entries = fs::read_dir(&self.cache_dir).await?;
        let mut total_size = 0;
        let mut files_to_remove = Vec::new();
        
        while let Some(entry) = entries.next_entry().await? {
            let metadata = entry.metadata().await?;
            total_size += metadata.len();
            
            // Remove files older than max_age
            if let Ok(modified) = metadata.modified() {
                if let Ok(age) = SystemTime::now().duration_since(modified) {
                    if age > self.max_age {
                        files_to_remove.push(entry.path());
                    }
                }
            }
        }
        
        // Remove old files
        for file_path in files_to_remove {
            let _ = fs::remove_file(file_path).await;
        }
        
        // If still over limit, remove oldest files
        if total_size > self.max_cache_size {
            self.remove_oldest_files().await?;
        }
        
        Ok(())
    }

    async fn remove_oldest_files(&self) -> anyhow::Result<()> {
        let mut entries = fs::read_dir(&self.cache_dir).await?;
        let mut file_entries = Vec::new();
        
        while let Some(entry) = entries.next_entry().await? {
            let metadata = entry.metadata().await?;
            let modified = metadata.modified().unwrap_or(UNIX_EPOCH);
            file_entries.push((entry, metadata, modified));
        }
        
        // Sort by modification time (oldest first)
        file_entries.sort_by_key(|(_, _, modified)| *modified);
        
        // Remove oldest files until under limit
        let mut total_size = 0;
        for (entry, metadata, _) in file_entries {
            total_size += metadata.len();
            
            if total_size > self.max_cache_size {
                let _ = fs::remove_file(entry.path()).await;
            }
        }
        
        Ok(())
    }

    pub async fn stream_track(&self, track_id: &str, range_header: Option<&str>) -> Result<Response, StatusCode> {
        println!("Streaming request for track_id: {} with range: {:?}", track_id, range_header);
        
        // Find the cached track
        let cached_track = {
            let cached_tracks = self.cached_tracks.read().await;
            println!("Total cached tracks: {}", cached_tracks.len());
            for (key, track) in cached_tracks.iter() {
                println!("Cached track key: {}, id: {}, path: {:?}", key, track.id, track.file_path);
            }
            cached_tracks.values()
                .find(|track| track.id == track_id)
                .cloned()
        };

        let cached_track = match cached_track {
            Some(track) => {
                println!("Found cached track: {:?}", track);
                track
            },
            None => {
                println!("No cached track found for ID: {}", track_id);
                return Err(StatusCode::NOT_FOUND);
            },
        };

        // Check if file exists
        if !cached_track.file_path.exists() {
            println!("Cached file does not exist: {:?}", cached_track.file_path);
            return Err(StatusCode::NOT_FOUND);
        }
        
        println!("File exists, reading content...");

        // Get file metadata
        let file_metadata = match fs::metadata(&cached_track.file_path).await {
            Ok(metadata) => metadata,
            Err(_) => return Err(StatusCode::INTERNAL_SERVER_ERROR),
        };

        let file_size = file_metadata.len() as usize;
        println!("File size: {} bytes", file_size);

        // Parse range header if present
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

        println!("Range: {} - {} (length: {})", start, end, end - start + 1);

        // Read the requested range
        let mut file = match fs::File::open(&cached_track.file_path).await {
            Ok(file) => file,
            Err(_) => return Err(StatusCode::INTERNAL_SERVER_ERROR),
        };

        // Seek to start position
        use tokio::io::AsyncSeekExt;
        if let Err(_) = file.seek(std::io::SeekFrom::Start(start as u64)).await {
            return Err(StatusCode::INTERNAL_SERVER_ERROR);
        }

        // Read the range
        let mut buffer = vec![0u8; end - start + 1];
        let bytes_read = match file.read_exact(&mut buffer).await {
            Ok(_) => buffer.len(),
            Err(_) => return Err(StatusCode::INTERNAL_SERVER_ERROR),
        };

        let content = buffer[..bytes_read].to_vec();

        // Create response with proper headers for range requests
        let mut response_builder = Response::builder()
            .header(header::CONTENT_TYPE, "audio/mpeg")
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

        let response = response_builder
            .body(content.into())
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        Ok(response)
    }

    pub fn router(streaming_service: Arc<StreamingService>) -> Router<AppState> {
        Router::new()
            .route("/api/stream/{track_id}", get(move |path: AxumPath<String>, headers: HeaderMap| {
                let service = streaming_service.clone();
                async move { 
                    let range_value = headers
                        .get(header::RANGE)
                        .and_then(|h| h.to_str().ok())
                        .map(|s| s.to_string());
                    stream_track_handler(service, path, range_value).await 
                }
            }))
    }
}

async fn stream_track_handler(
    streaming_service: Arc<StreamingService>,
    AxumPath(track_id): AxumPath<String>,
    range_header: Option<String>,
) -> Result<Response, StatusCode> {
    streaming_service.stream_track(&track_id, range_header.as_deref()).await
}
