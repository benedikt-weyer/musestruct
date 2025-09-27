use async_trait::async_trait;
use std::path::{Path, PathBuf};
use std::collections::HashMap;
use tokio::fs;
use serde::{Deserialize, Serialize};
use anyhow::{Result, anyhow};

use super::{StreamingService, SearchResults, StreamingTrack, StreamingAlbum, StreamingPlaylist, ServiceCredentials, AuthResult};

#[derive(Debug, Clone)]
pub struct LocalMusicService {
    music_dir: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalTrack {
    pub file_path: PathBuf,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<u32>,
    pub file_name: String,
}

impl LocalMusicService {
    pub fn new(music_dir: PathBuf) -> Self {
        Self { music_dir }
    }

    async fn scan_music_files(&self) -> Result<Vec<LocalTrack>, String> {
        let mut tracks = Vec::new();
        
        if !self.music_dir.exists() {
            // Create the directory if it doesn't exist
            if let Err(e) = fs::create_dir_all(&self.music_dir).await {
                return Err(format!("Failed to create music directory: {}", e));
            }
            return Ok(tracks);
        }

        // Recursively scan the directory and its subdirectories
        self.scan_directory_recursive(&self.music_dir, &mut tracks).await?;

        Ok(tracks)
    }

    fn scan_directory_recursive<'a>(&'a self, dir: &'a std::path::Path, tracks: &'a mut Vec<LocalTrack>) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), String>> + Send + 'a>> {
        Box::pin(async move {
            let mut entries = match fs::read_dir(dir).await {
                Ok(entries) => entries,
                Err(e) => return Err(format!("Failed to read directory {:?}: {}", dir, e)),
            };

            while let Some(entry) = entries.next_entry().await.map_err(|e| format!("Error reading directory entry: {}", e))? {
                let path = entry.path();
                
                if path.is_file() {
                    if let Some(extension) = path.extension() {
                        let ext = extension.to_string_lossy().to_lowercase();
                        if matches!(ext.as_str(), "mp3" | "flac" | "wav" | "m4a" | "ogg") {
                            let file_name = path.file_name()
                                .unwrap_or_default()
                                .to_string_lossy()
                                .to_string();
                            
                            // Extract metadata from filename and directory structure
                            let (title, artist, album) = self.parse_file_metadata(&path);
                            
                            tracks.push(LocalTrack {
                                file_path: path.clone(),
                                title,
                                artist,
                                album,
                                duration: None, // Could be extracted with a metadata library
                                file_name,
                            });
                        }
                    }
                } else if path.is_dir() {
                    // Recursively scan subdirectories
                    self.scan_directory_recursive(&path, tracks).await?;
                }
            }

            Ok(())
        })
    }

    fn parse_file_metadata(&self, file_path: &std::path::Path) -> (String, String, String) {
        let filename = file_path.file_name()
            .unwrap_or_default()
            .to_string_lossy();
        
        // Try to extract artist and album from directory structure
        // Expected structure: .../Artist/Album/Track.mp3 or .../Artist/Track.mp3
        let mut artist = "Unknown Artist".to_string();
        let mut album = "Unknown Album".to_string();
        
        if let Some(parent) = file_path.parent() {
            if let Some(album_name) = parent.file_name() {
                album = album_name.to_string_lossy().to_string();
                
                // Check if there's a parent directory for artist
                if let Some(grandparent) = parent.parent() {
                    if let Some(artist_name) = grandparent.file_name() {
                        // Skip the root music directory names
                        let artist_str = artist_name.to_string_lossy();
                        if artist_str != "own_music" && artist_str != "music_sl" && artist_str != "Musik" {
                            artist = artist_str.to_string();
                        }
                    }
                }
            }
        }
        
        // Parse title from filename
        let title = self.parse_title_from_filename(&filename);
        
        (title, artist, album)
    }

    fn parse_title_from_filename(&self, filename: &str) -> String {
        // Remove file extension
        let name_without_ext = filename.rsplit('.').nth(1).unwrap_or(filename);
        
        // Try to parse common formats:
        // "01 - Title.mp3" -> "Title"
        // "01. Title.mp3" -> "Title"
        // "Artist - Title.mp3" -> "Title"
        // "Title.mp3" -> "Title"
        
        let cleaned = name_without_ext.trim();
        
        // Remove track numbers at the beginning
        let without_track_num = if let Some(rest) = cleaned.strip_prefix(|c: char| c.is_ascii_digit()) {
            // Handle formats like "01 - Title" or "01. Title"
            if let Some(title) = rest.strip_prefix(" - ") {
                title
            } else if let Some(title) = rest.strip_prefix(". ") {
                title
            } else if let Some(title) = rest.strip_prefix(" ") {
                title
            } else {
                cleaned
            }
        } else {
            cleaned
        };
        
        // Handle "Artist - Title" format (if not already handled by directory structure)
        if let Some((_, title_part)) = without_track_num.split_once(" - ") {
            title_part.trim().to_string()
        } else {
            without_track_num.trim().to_string()
        }
    }

    fn get_stream_url_for_track(&self, track: &LocalTrack) -> String {
        // Get the relative path from the music directory
        if let Ok(relative_path) = track.file_path.strip_prefix(&self.music_dir) {
            format!("/api/stream/local/{}", urlencoding::encode(&relative_path.to_string_lossy()))
        } else {
            // Fallback to just the filename
            format!("/api/stream/local/{}", urlencoding::encode(&track.file_name))
        }
    }

    fn search_tracks(&self, tracks: &[LocalTrack], query: &str) -> Vec<StreamingTrack> {
        let query_lower = query.to_lowercase();
        
        tracks.iter()
            .filter(|track| {
                track.title.to_lowercase().contains(&query_lower) ||
                track.artist.to_lowercase().contains(&query_lower) ||
                track.album.to_lowercase().contains(&query_lower) ||
                track.file_name.to_lowercase().contains(&query_lower)
            })
            .map(|track| StreamingTrack {
                id: format!("server_{}", track.file_path.to_string_lossy()),
                title: track.title.clone(),
                artist: track.artist.clone(),
                album: track.album.clone(),
                            duration: track.duration.map(|d| d as i32),
                            stream_url: Some(self.get_stream_url_for_track(track)),
                cover_url: None,
                source: "server".to_string(),
                quality: Some("Original".to_string()),
                bitrate: None,
                sample_rate: None,
                bit_depth: None,
            })
            .collect()
    }

    fn search_albums(&self, tracks: &[LocalTrack], query: &str) -> Vec<StreamingAlbum> {
        let query_lower = query.to_lowercase();
        let mut albums: HashMap<String, Vec<&LocalTrack>> = HashMap::new();
        
        // Group tracks by album
        for track in tracks {
            if track.album.to_lowercase().contains(&query_lower) ||
               track.artist.to_lowercase().contains(&query_lower) {
                let album_key = format!("{}_{}", track.artist, track.album);
                albums.entry(album_key).or_insert_with(Vec::new).push(track);
            }
        }
        
        albums.into_iter()
            .map(|(_, album_tracks)| {
                let first_track = album_tracks[0];
                
                // Sort tracks by filename to get a consistent order
                let mut sorted_tracks = album_tracks;
                sorted_tracks.sort_by(|a, b| a.file_name.cmp(&b.file_name));
                
                StreamingAlbum {
                    id: format!("server_album_{}_{}", 
                        urlencoding::encode(&first_track.artist),
                        urlencoding::encode(&first_track.album)
                    ),
                    title: first_track.album.clone(),
                    artist: first_track.artist.clone(),
                    release_date: None,
                    cover_url: None,
                    tracks: sorted_tracks.iter().map(|track| StreamingTrack {
                        id: format!("server_{}", track.file_path.to_string_lossy()),
                        title: track.title.clone(),
                        artist: track.artist.clone(),
                        album: track.album.clone(),
                        duration: track.duration.map(|d| d as i32),
                        stream_url: Some(self.get_stream_url_for_track(track)),
                        cover_url: None,
                        source: "server".to_string(),
                        quality: Some("Original".to_string()),
                        bitrate: None,
                        sample_rate: None,
                        bit_depth: None,
                    }).collect(),
                    source: "server".to_string(),
                }
            })
            .collect()
    }
}

#[async_trait]
impl StreamingService for LocalMusicService {
    async fn search(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        let tracks = self.scan_music_files().await.map_err(|e| anyhow!(e))?;
        
        let found_tracks = self.search_tracks(&tracks, query);
        let found_albums = self.search_albums(&tracks, query);
        
        let limit = limit.unwrap_or(20) as usize;
        let offset = offset.unwrap_or(0) as usize;
        
        let total_tracks = found_tracks.len();
        let total_albums = found_albums.len();
        
        let paginated_tracks = found_tracks.into_iter()
            .skip(offset)
            .take(limit)
            .collect();
            
        let paginated_albums = found_albums.into_iter()
            .skip(offset)
            .take(limit)
            .collect();
        
        Ok(SearchResults {
            tracks: paginated_tracks,
            albums: paginated_albums,
            playlists: Vec::new(), // Server doesn't support playlists
            total: (total_tracks + total_albums) as u32,
            offset: offset as u32,
            limit: limit as u32,
        })
    }

    async fn search_playlists(&self, _query: &str, _limit: Option<u32>, _offset: Option<u32>) -> Result<Vec<StreamingPlaylist>> {
        // Server doesn't support playlists
        Ok(Vec::new())
    }

    async fn get_playlist_tracks(&self, _playlist_id: &str, _limit: Option<u32>, _offset: Option<u32>) -> Result<Vec<StreamingTrack>> {
        // Server doesn't support playlists
        Ok(Vec::new())
    }

    async fn get_album_tracks(&self, album_id: &str) -> Result<Vec<StreamingTrack>> {
        // Parse album_id format: "server_album_{artist}_{album}"
        if let Some(album_part) = album_id.strip_prefix("server_album_") {
            // Decode the URL-encoded artist and album names
            let parts: Vec<&str> = album_part.splitn(2, '_').collect();
            if parts.len() == 2 {
                let artist = urlencoding::decode(parts[0]).map_err(|e| anyhow!("Failed to decode artist: {}", e))?.into_owned();
                let album = urlencoding::decode(parts[1]).map_err(|e| anyhow!("Failed to decode album: {}", e))?.into_owned();
                
                // Scan all music files and filter by artist and album
                let all_tracks = self.scan_music_files().await.map_err(|e| anyhow!(e))?;
                
                let album_tracks: Vec<StreamingTrack> = all_tracks.iter()
                    .filter(|track| track.artist == artist && track.album == album)
                    .map(|track| StreamingTrack {
                        id: format!("server_{}", track.file_path.to_string_lossy()),
                        title: track.title.clone(),
                        artist: track.artist.clone(),
                        album: track.album.clone(),
                        duration: track.duration.map(|d| d as i32),
                        stream_url: Some(self.get_stream_url_for_track(track)),
                        cover_url: None,
                        source: "server".to_string(),
                        quality: Some("Original".to_string()),
                        bitrate: None,
                        sample_rate: None,
                        bit_depth: None,
                    })
                    .collect();
                
                return Ok(album_tracks);
            }
        }
        
        Err(anyhow!("Invalid album ID format for server source"))
    }

    async fn get_stream_url(&self, track_id: &str, _quality: Option<&str>) -> Result<String> {
        // Extract file path from track_id (format: "server_/path/to/file")
        if let Some(file_path_str) = track_id.strip_prefix("server_") {
            let file_path = Path::new(file_path_str);
            
            // Get the relative path from the music directory
            if let Ok(relative_path) = file_path.strip_prefix(&self.music_dir) {
                return Ok(format!("/api/stream/local/{}", urlencoding::encode(&relative_path.to_string_lossy())));
            } else {
                // Fallback: if it's already a relative path or filename
                if let Some(filename) = file_path.file_name() {
                    return Ok(format!("/api/stream/local/{}", urlencoding::encode(&filename.to_string_lossy())));
                }
            }
        }
        
        Err(anyhow!("Invalid track ID for server source"))
    }

    async fn get_track(&self, track_id: &str) -> Result<StreamingTrack> {
        // For now, return error - could be implemented to get specific track details
        Err(anyhow!("Get track not implemented for server source"))
    }

    async fn authenticate(&self, _credentials: &ServiceCredentials) -> Result<AuthResult> {
        // Local service doesn't need authentication
        Ok(AuthResult {
            access_token: None,
            refresh_token: None,
            expires_at: None,
            user_id: None,
        })
    }

    async fn is_authenticated(&self) -> bool {
        // Local service is always "authenticated"
        true
    }

    fn service_name(&self) -> &str {
        "server"
    }
}
