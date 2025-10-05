use async_trait::async_trait;
use std::path::{Path, PathBuf};
use std::collections::HashMap;
use tokio::fs;
use serde::{Deserialize, Serialize};
use anyhow::{Result, anyhow};
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{MetadataOptions, StandardTagKey, Visual};
use symphonia::core::probe::Hint;
use std::fs::File;
use id3::{Tag, TagLike};
use sha2::{Sha256, Digest};

use super::{StreamingService, SearchResults, StreamingTrack, StreamingAlbum, StreamingPlaylist, ServiceCredentials, AuthResult};

#[derive(Debug, Clone)]
struct TrackMetadata {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<u32>,
    pub cover_url: Option<String>,
    pub track_number: Option<u32>,
    pub year: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct LocalMusicService {
    music_dir: PathBuf,
    cache_dir: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalTrack {
    pub file_path: PathBuf,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<u32>,
    pub file_name: String,
    pub cover_url: Option<String>,
    pub track_number: Option<u32>,
    pub year: Option<u32>,
}

impl LocalMusicService {
    pub fn new(music_dir: PathBuf) -> Self {
        let cache_dir = std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join("cache")
            .join("covers");
        
        // Create cache directory if it doesn't exist
        if let Err(e) = std::fs::create_dir_all(&cache_dir) {
            eprintln!("Warning: Failed to create cover cache directory: {}", e);
        }
        
        Self { 
            music_dir,
            cache_dir,
        }
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
                            
                            // Extract metadata from file tags and directory structure
                            let metadata = self.extract_metadata(&path).await;
                            
                            tracks.push(LocalTrack {
                                file_path: path.clone(),
                                title: metadata.title,
                                artist: metadata.artist,
                                album: metadata.album,
                                duration: metadata.duration,
                                file_name,
                                cover_url: metadata.cover_url,
                                track_number: metadata.track_number,
                                year: metadata.year,
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

    async fn extract_metadata(&self, file_path: &std::path::Path) -> TrackMetadata {
        println!("Extracting metadata for file: {:?}", file_path);
        
        // First try to extract metadata from the audio file tags
        match self.extract_audio_metadata(file_path) {
            Ok(metadata) => {
                println!("Successfully extracted metadata from tags for: {:?}", file_path.file_name());
                println!("  Title: '{}', Artist: '{}', Album: '{}'", metadata.title, metadata.artist, metadata.album);
                metadata
            },
            Err(e) => {
                println!("Failed to extract metadata from tags for {:?}: {}. Falling back to folder structure.", file_path.file_name(), e);
                // Fallback to parsing from filename and directory structure
                let fallback = self.parse_file_metadata(file_path);
                println!("Fallback metadata - Title: '{}', Artist: '{}', Album: '{}'", fallback.title, fallback.artist, fallback.album);
                fallback
            }
        }
    }

    fn extract_audio_metadata(&self, file_path: &std::path::Path) -> Result<TrackMetadata> {
        println!("Attempting to read ID3 tags from: {:?}", file_path);
        
        // Try to read ID3 tags using the id3 crate
        let tag = Tag::read_from_path(file_path)
            .map_err(|e| anyhow!("Failed to read ID3 tags: {}", e))?;
        
        println!("Successfully read ID3 tag");
        
        // Extract basic metadata
        let title = tag.title().map(|s| s.to_string());
        let artist = tag.artist().map(|s| s.to_string());
        let album = tag.album().map(|s| s.to_string());
        let track_number = tag.track();
        let year = tag.year();
        
        println!("ID3 metadata - title: {:?}, artist: {:?}, album: {:?}, track: {:?}, year: {:?}", 
                 title, artist, album, track_number, year);
        
        // Get duration using Symphonia (since id3 doesn't provide duration)
        let duration = self.get_duration_from_symphonia(file_path).unwrap_or(None);
        
        // Look for cover image
        let cover_url = self.find_cover_image(file_path);
        
        // Check if we have any essential metadata
        let has_essential_metadata = title.is_some() || artist.is_some() || album.is_some();
        
        if !has_essential_metadata {
            println!("No essential metadata found in ID3 tags, falling back to folder structure");
            return Err(anyhow!("No essential metadata found in ID3 tags"));
        }
        
        // Use fallback values only for missing fields
        let fallback_metadata = self.parse_file_metadata(file_path);
        
        let final_metadata = TrackMetadata {
            title: title.unwrap_or(fallback_metadata.title),
            artist: artist.unwrap_or(fallback_metadata.artist),
            album: album.unwrap_or(fallback_metadata.album),
            duration,
            cover_url,
            track_number,
            year: year.map(|y| y as u32), // Convert i32 to u32
        };
        
        println!("Final ID3 metadata - title: '{}', artist: '{}', album: '{}'", 
                 final_metadata.title, final_metadata.artist, final_metadata.album);
        
        Ok(final_metadata)
    }
    
    fn get_duration_from_symphonia(&self, file_path: &std::path::Path) -> Result<Option<u32>> {
        let file = File::open(file_path)
            .map_err(|e| anyhow!("Failed to open file for duration: {}", e))?;
        
        let mss = MediaSourceStream::new(Box::new(file), Default::default());
        
        let mut hint = Hint::new();
        if let Some(extension) = file_path.extension() {
            if let Some(ext_str) = extension.to_str() {
                hint.with_extension(ext_str);
            }
        }
        
        let meta_opts: MetadataOptions = Default::default();
        let fmt_opts: FormatOptions = Default::default();
        
        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &fmt_opts, &meta_opts)
            .map_err(|e| anyhow!("Failed to probe audio format for duration: {}", e))?;
        
        let format = probed.format;
        
        // Get duration from track info
        let duration = if let Some(track) = format.tracks().iter().next() {
            if let Some(time_base) = track.codec_params.time_base {
                if let Some(n_frames) = track.codec_params.n_frames {
                    Some((n_frames as f64 * time_base.numer as f64 / time_base.denom as f64) as u32)
                } else {
                    None
                }
            } else {
                None
            }
        } else {
            None
        };
        
        Ok(duration)
    }

    fn find_cover_image(&self, audio_file_path: &std::path::Path) -> Option<String> {
        // PREFERRED METHOD: Extract embedded cover art from audio file
        if let Some(cached_cover_url) = self.extract_and_cache_embedded_cover(audio_file_path) {
            return Some(cached_cover_url);
        }
        
        // FALLBACK 1: Look for external image files
        let audio_stem = audio_file_path.file_stem()?.to_string_lossy();
        let parent_dir = audio_file_path.parent()?;
        
        // Common cover image names
        let cover_names = ["cover", "folder", "album", "front"];
        let image_extensions = ["jpg", "jpeg", "png", "bmp", "gif"];
        
        // First, look for images with the same name as the audio file
        for ext in &image_extensions {
            let cover_path = parent_dir.join(format!("{}.{}", audio_stem, ext));
            if cover_path.exists() {
                if let Ok(relative_path) = cover_path.strip_prefix(&self.music_dir) {
                    return Some(format!("/api/stream/local/cover/{}", urlencoding::encode(&relative_path.to_string_lossy())));
                }
            }
        }
        
        // Then look for common cover image names
        for name in &cover_names {
            for ext in &image_extensions {
                let cover_path = parent_dir.join(format!("{}.{}", name, ext));
                if cover_path.exists() {
                    if let Ok(relative_path) = cover_path.strip_prefix(&self.music_dir) {
                        return Some(format!("/api/stream/local/cover/{}", urlencoding::encode(&relative_path.to_string_lossy())));
                    }
                }
            }
        }
        
        None
    }
    
    /// Extract embedded cover art from audio files and cache it
    /// Returns the URL to the cached cover image
    fn extract_and_cache_embedded_cover(&self, audio_file_path: &std::path::Path) -> Option<String> {
        // Generate a unique hash for this audio file based on its path
        let file_path_str = audio_file_path.to_string_lossy();
        let mut hasher = Sha256::new();
        hasher.update(file_path_str.as_bytes());
        let hash = hasher.finalize();
        let hash_hex = format!("{:x}", hash);
        
        // Check if we already have a cached cover for this file
        let cache_extensions = ["jpg", "jpeg", "png"];
        for ext in &cache_extensions {
            let cached_path = self.cache_dir.join(format!("{}.{}", hash_hex, ext));
            if cached_path.exists() {
                // Return URL to cached cover
                return Some(format!("/api/stream/local/cover/cached/{}.{}", hash_hex, ext));
            }
        }
        
        // Try to extract cover art from the audio file
        let cover_data = self.extract_cover_from_audio(audio_file_path)?;
        
        // Determine image format and save to cache
        let image_format = self.detect_image_format(&cover_data);
        let cache_filename = format!("{}.{}", hash_hex, image_format);
        let cache_path = self.cache_dir.join(&cache_filename);
        
        // Write the cover data to cache
        if let Err(e) = std::fs::write(&cache_path, &cover_data) {
            eprintln!("Failed to cache cover art for {:?}: {}", audio_file_path, e);
            return None;
        }
        
        println!("Cached cover art for {:?} as {}", audio_file_path.file_name()?, cache_filename);
        
        // Return URL to cached cover
        Some(format!("/api/stream/local/cover/cached/{}", cache_filename))
    }
    
    /// Extract cover art from audio file using multiple methods
    fn extract_cover_from_audio(&self, file_path: &std::path::Path) -> Option<Vec<u8>> {
        // Try Symphonia first (supports FLAC, MP3, M4A, OGG, WAV, and more)
        if let Some(cover) = self.extract_cover_with_symphonia(file_path) {
            return Some(cover);
        }
        
        // Fallback to ID3 for MP3 files (more comprehensive MP3 support)
        if let Some(ext) = file_path.extension() {
            if ext.to_string_lossy().to_lowercase() == "mp3" {
                if let Some(cover) = self.extract_cover_with_id3(file_path) {
                    return Some(cover);
                }
            }
        }
        
        None
    }
    
    /// Extract cover art using Symphonia (supports most audio formats)
    fn extract_cover_with_symphonia(&self, file_path: &std::path::Path) -> Option<Vec<u8>> {
        let file = File::open(file_path).ok()?;
        let mss = MediaSourceStream::new(Box::new(file), Default::default());
        
        let mut hint = Hint::new();
        if let Some(extension) = file_path.extension() {
            if let Some(ext_str) = extension.to_str() {
                hint.with_extension(ext_str);
            }
        }
        
        let meta_opts: MetadataOptions = Default::default();
        let fmt_opts: FormatOptions = Default::default();
        
        let mut probed = symphonia::default::get_probe()
            .format(&hint, mss, &fmt_opts, &meta_opts)
            .ok()?;
        
        // Check metadata for visual (cover art)
        if let Some(metadata_rev) = probed.format.metadata().current() {
            for visual in metadata_rev.visuals() {
                // Return the first cover art found
                if matches!(visual.usage, Some(symphonia::core::meta::StandardVisualKey::FrontCover) | None) {
                    return Some(visual.data.to_vec());
                }
            }
            // If no front cover, return any visual
            if let Some(visual) = metadata_rev.visuals().first() {
                return Some(visual.data.to_vec());
            }
        }
        
        // Also check track-level metadata
        if let Some(track) = probed.format.tracks().iter().next() {
            // Some formats store metadata at track level
            // This is already handled by metadata().current() in most cases
        }
        
        None
    }
    
    /// Extract cover art using ID3 tags (MP3 specific)
    fn extract_cover_with_id3(&self, file_path: &std::path::Path) -> Option<Vec<u8>> {
        let tag = Tag::read_from_path(file_path).ok()?;
        
        // Look for picture frames (APIC)
        for picture in tag.pictures() {
            // Prefer front cover, but accept any picture
            if picture.picture_type == id3::frame::PictureType::CoverFront 
               || picture.picture_type == id3::frame::PictureType::Other {
                return Some(picture.data.to_vec());
            }
        }
        
        // If no front cover found, return first picture
        if let Some(picture) = tag.pictures().next() {
            return Some(picture.data.to_vec());
        }
        
        None
    }
    
    /// Detect image format from raw bytes
    fn detect_image_format(&self, data: &[u8]) -> &'static str {
        if data.len() < 12 {
            return "jpg"; // Default fallback
        }
        
        // Check PNG signature
        if data.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png";
        }
        
        // Check JPEG signature
        if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
            return "jpg";
        }
        
        // Check GIF signature
        if data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a") {
            return "gif";
        }
        
        // Check BMP signature
        if data.starts_with(b"BM") {
            return "bmp";
        }
        
        // Check WebP signature
        if data.len() >= 12 && data.starts_with(b"RIFF") && &data[8..12] == b"WEBP" {
            return "webp";
        }
        
        "jpg" // Default fallback
    }

    fn parse_file_metadata(&self, file_path: &std::path::Path) -> TrackMetadata {
        let filename = file_path.file_name()
            .unwrap_or_default()
            .to_string_lossy();
        
        // Try to extract artist and album from directory structure
        // Expected structures: 
        // .../Artist/Album/Track.mp3
        // .../Artist/Track.mp3
        // .../Album/Track.mp3
        let mut artist = "Unknown Artist".to_string();
        let mut album = "Unknown Album".to_string();
        
        if let Some(parent) = file_path.parent() {
            if let Some(album_name) = parent.file_name() {
                let album_str = album_name.to_string_lossy().to_string();
                
                // Check if there's a parent directory for artist
                if let Some(grandparent) = parent.parent() {
                    if let Some(artist_name) = grandparent.file_name() {
                        let artist_str = artist_name.to_string_lossy().to_string();
                        
                        // Skip common root directory names
                        let skip_names = ["own_music", "music_sl", "Musik", "Music", "music", "Audio", "audio"];
                        if !skip_names.contains(&artist_str.as_str()) && 
                           !artist_str.starts_with('/') && 
                           artist_str.len() > 1 {
                            artist = artist_str;
                            album = album_str;
                        } else {
                            // If grandparent is a root dir, treat parent as artist
                            artist = album_str;
                            album = "Unknown Album".to_string();
                        }
                    } else {
                        // No grandparent, treat parent as artist
                        artist = album_str;
                        album = "Unknown Album".to_string();
                    }
                } else {
                    // No parent directory, treat current dir as artist
                    artist = album_str;
                    album = "Unknown Album".to_string();
                }
            }
        }
        
        // Parse title from filename
        let title = self.parse_title_from_filename(&filename);
        
        TrackMetadata {
            title,
            artist,
            album,
            duration: None,
            cover_url: self.find_cover_image(file_path),
            track_number: None,
            year: None,
        }
    }

    fn parse_title_from_filename(&self, filename: &str) -> String {
        // Remove file extension
        let name_without_ext = if let Some(dot_pos) = filename.rfind('.') {
            &filename[..dot_pos]
        } else {
            filename
        };
        
        let cleaned = name_without_ext.trim();
        
        // Handle various filename formats:
        // "01 - Title" -> "Title"
        // "01. Title" -> "Title"  
        // "01 Title" -> "Title"
        // "Artist - Title" -> "Title"
        // "Title" -> "Title"
        
        // First, try to remove track numbers at the beginning
        let without_track_num = if let Some(first_char) = cleaned.chars().next() {
            if first_char.is_ascii_digit() {
                // Find where the track number ends
                let mut end_pos = 0;
                for (i, c) in cleaned.char_indices() {
                    if c.is_ascii_digit() {
                        end_pos = i + 1;
                    } else {
                        break;
                    }
                }
                
                // Skip track number and any following separators
                let rest = &cleaned[end_pos..];
                if let Some(title) = rest.strip_prefix(" - ") {
                    title
                } else if let Some(title) = rest.strip_prefix(". ") {
                    title
                } else if let Some(title) = rest.strip_prefix(" ") {
                    title
                } else if let Some(title) = rest.strip_prefix("-") {
                    title.trim()
                } else if let Some(title) = rest.strip_prefix(".") {
                    title.trim()
                } else if !rest.is_empty() {
                    rest
                } else {
                    cleaned
                }
            } else {
                cleaned
            }
        } else {
            cleaned
        };
        
        // Handle "Artist - Title" format (only if we haven't already extracted from directory)
        let final_title = if let Some((_, title_part)) = without_track_num.split_once(" - ") {
            title_part.trim()
        } else if let Some((_, title_part)) = without_track_num.split_once(" – ") { // em dash
            title_part.trim()
        } else {
            without_track_num.trim()
        };
        
        // If the result is empty or too short, use the original filename
        if final_title.is_empty() || final_title.len() < 2 {
            cleaned.to_string()
        } else {
            final_title.to_string()
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
                // If query is empty, return all tracks
                if query.trim().is_empty() {
                    true
                } else {
                    track.title.to_lowercase().contains(&query_lower) ||
                    track.artist.to_lowercase().contains(&query_lower) ||
                    track.album.to_lowercase().contains(&query_lower) ||
                    track.file_name.to_lowercase().contains(&query_lower)
                }
            })
            .map(|track| StreamingTrack {
                id: format!("server_{}", track.file_path.to_string_lossy()),
                title: track.title.clone(),
                artist: track.artist.clone(),
                album: track.album.clone(),
                duration: track.duration.map(|d| d as i32),
                stream_url: Some(self.get_stream_url_for_track(track)),
                cover_url: track.cover_url.clone(),
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
        
        // Group tracks by album using metadata
        for track in tracks {
            // If query is empty, include all albums
            let matches = if query.trim().is_empty() {
                true
            } else {
                track.album.to_lowercase().contains(&query_lower) ||
                track.artist.to_lowercase().contains(&query_lower)
            };
            
            if matches {
                let album_key = format!("{}_{}", track.artist, track.album);
                albums.entry(album_key).or_insert_with(Vec::new).push(track);
            }
        }
        
        albums.into_iter()
            .map(|(_, album_tracks)| {
                let first_track = album_tracks[0];
                
                // Sort tracks by track number if available, otherwise by filename
                let mut sorted_tracks = album_tracks;
                sorted_tracks.sort_by(|a, b| {
                    match (a.track_number, b.track_number) {
                        (Some(a_num), Some(b_num)) => a_num.cmp(&b_num),
                        (Some(_), None) => std::cmp::Ordering::Less,
                        (None, Some(_)) => std::cmp::Ordering::Greater,
                        (None, None) => a.file_name.cmp(&b.file_name),
                    }
                });
                
                // Get release date from the first track that has a year
                let release_date = sorted_tracks.iter()
                    .find_map(|track| track.year)
                    .map(|year| year.to_string());
                
                // Use cover from first track that has one
                let cover_url = sorted_tracks.iter()
                    .find_map(|track| track.cover_url.as_ref())
                    .cloned();
                
                StreamingAlbum {
                    id: format!("server_album_{}_{}", 
                        urlencoding::encode(&first_track.artist),
                        urlencoding::encode(&first_track.album)
                    ),
                    title: first_track.album.clone(),
                    artist: first_track.artist.clone(),
                    release_date,
                    cover_url,
                    tracks: sorted_tracks.iter().map(|track| StreamingTrack {
                        id: format!("server_{}", track.file_path.to_string_lossy()),
                        title: track.title.clone(),
                        artist: track.artist.clone(),
                        album: track.album.clone(),
                        duration: track.duration.map(|d| d as i32),
                        stream_url: Some(self.get_stream_url_for_track(track)),
                        cover_url: track.cover_url.clone(),
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

    async fn scan_playlists(&self) -> Result<Vec<StreamingPlaylist>, String> {
        let mut playlists = Vec::new();
        self.scan_playlists_recursive(&self.music_dir, &mut playlists, String::new()).await?;
        Ok(playlists)
    }

    fn scan_playlists_recursive<'a>(&'a self, dir: &'a std::path::Path, playlists: &'a mut Vec<StreamingPlaylist>, parent_path: String) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), String>> + Send + 'a>> {
        Box::pin(async move {
            let mut entries = match fs::read_dir(dir).await {
                Ok(entries) => entries,
                Err(e) => return Err(format!("Failed to read directory {:?}: {}", dir, e)),
            };

            while let Some(entry) = entries.next_entry().await.map_err(|e| format!("Error reading directory entry: {}", e))? {
                let path = entry.path();
                
                if path.is_dir() {
                    let dir_name = path.file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .to_string();
                    
                    // Skip root music directory names
                    if matches!(dir_name.as_str(), "own_music" | "music_sl" | "Musik") {
                        self.scan_playlists_recursive(&path, playlists, parent_path.clone()).await?;
                        continue;
                    }

                    // Count audio files in this directory (not recursive for track count)
                    let track_count = self.count_audio_files_in_directory(&path).await;
                    
                    if track_count > 0 {
                        let playlist_name = if parent_path.is_empty() {
                            dir_name.clone()
                        } else {
                            format!("{}/{}", parent_path, dir_name)
                        };

                        // Look for cover image in this directory
                        let cover_url = self.find_directory_cover(&path);

                        let playlist_id = if let Ok(relative_path) = path.strip_prefix(&self.music_dir) {
                            format!("server_playlist_{}", urlencoding::encode(&relative_path.to_string_lossy()))
                        } else {
                            format!("server_playlist_{}", urlencoding::encode(&dir_name))
                        };

                        playlists.push(StreamingPlaylist {
                            id: playlist_id,
                            name: playlist_name,
                            description: Some(format!("Folder-based playlist: {}", dir_name)),
                            owner: "Local".to_string(),
                            source: "server".to_string(),
                            cover_url,
                            track_count,
                            is_public: false,
                            external_url: None,
                        });
                    }

                    // Recursively scan subdirectories
                    let new_parent_path = if parent_path.is_empty() {
                        dir_name
                    } else {
                        format!("{}/{}", parent_path, dir_name)
                    };
                    self.scan_playlists_recursive(&path, playlists, new_parent_path).await?;
                }
            }

            Ok(())
        })
    }

    async fn count_audio_files_in_directory(&self, dir: &std::path::Path) -> u32 {
        let mut count = 0;
        if let Ok(mut entries) = fs::read_dir(dir).await {
            while let Ok(Some(entry)) = entries.next_entry().await {
                let path = entry.path();
                if path.is_file() {
                    if let Some(extension) = path.extension() {
                        let ext = extension.to_string_lossy().to_lowercase();
                        if matches!(ext.as_str(), "mp3" | "flac" | "wav" | "m4a" | "ogg") {
                            count += 1;
                        }
                    }
                }
            }
        }
        count
    }

    fn find_directory_cover(&self, dir_path: &std::path::Path) -> Option<String> {
        let cover_names = ["cover", "folder", "album", "front"];
        let image_extensions = ["jpg", "jpeg", "png", "bmp", "gif"];
        
        // First, look for external cover images
        for name in &cover_names {
            for ext in &image_extensions {
                let cover_path = dir_path.join(format!("{}.{}", name, ext));
                if cover_path.exists() {
                    if let Ok(relative_path) = cover_path.strip_prefix(&self.music_dir) {
                        return Some(format!("/api/stream/local/cover/{}", urlencoding::encode(&relative_path.to_string_lossy())));
                    }
                }
            }
        }
        
        // Fallback: Try to extract cover from the first audio file in the directory
        if let Ok(entries) = std::fs::read_dir(dir_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_file() {
                    if let Some(extension) = path.extension() {
                        let ext = extension.to_string_lossy().to_lowercase();
                        if matches!(ext.as_str(), "mp3" | "flac" | "wav" | "m4a" | "ogg") {
                            // Try to extract and cache cover from this audio file
                            if let Some(cover_url) = self.extract_and_cache_embedded_cover(&path) {
                                return Some(cover_url);
                            }
                        }
                    }
                }
            }
        }
        
        None
    }

    fn search_playlists(&self, playlists: &[StreamingPlaylist], query: &str) -> Vec<StreamingPlaylist> {
        let query_lower = query.to_lowercase();
        
        playlists.iter()
            .filter(|playlist| {
                // If query is empty, return all playlists
                if query.trim().is_empty() {
                    true
                } else {
                    playlist.name.to_lowercase().contains(&query_lower) ||
                    playlist.description.as_ref().map_or(false, |desc| desc.to_lowercase().contains(&query_lower))
                }
            })
            .cloned()
            .collect()
    }

    async fn get_playlist_tracks_by_path(&self, playlist_path: &std::path::Path) -> Result<Vec<StreamingTrack>> {
        let mut tracks = Vec::new();
        self.scan_directory_recursive(playlist_path, &mut tracks).await
            .map_err(|e| anyhow!("Failed to scan playlist directory: {}", e))?;
        
        // Sort tracks by track number if available, otherwise by filename
        tracks.sort_by(|a, b| {
            match (a.track_number, b.track_number) {
                (Some(a_num), Some(b_num)) => a_num.cmp(&b_num),
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => a.file_name.cmp(&b.file_name),
            }
        });

        Ok(tracks.into_iter().map(|track| {
            let local_track = LocalTrack {
                file_path: track.file_path.clone(),
                title: track.title.clone(),
                artist: track.artist.clone(),
                album: track.album.clone(),
                duration: track.duration,
                file_name: track.file_name.clone(),
                cover_url: track.cover_url.clone(),
                track_number: track.track_number,
                year: track.year,
            };
            
            StreamingTrack {
                id: format!("server_{}", track.file_path.to_string_lossy()),
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration.map(|d| d as i32),
                stream_url: Some(self.get_stream_url_for_track(&local_track)),
                cover_url: track.cover_url,
                source: "server".to_string(),
                quality: Some("Original".to_string()),
                bitrate: None,
                sample_rate: None,
                bit_depth: None,
            }
        }).collect())
    }
}

#[async_trait]
impl StreamingService for LocalMusicService {
    async fn search(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        let tracks = self.scan_music_files().await.map_err(|e| anyhow!(e))?;
        let playlists = self.scan_playlists().await.map_err(|e| anyhow!(e))?;
        
        let found_tracks = self.search_tracks(&tracks, query);
        let found_albums = self.search_albums(&tracks, query);
        let found_playlists = self.search_playlists(&playlists, query);
        
        let limit = limit.unwrap_or(20) as usize;
        let offset = offset.unwrap_or(0) as usize;
        
        let total_tracks = found_tracks.len();
        let total_albums = found_albums.len();
        let total_playlists = found_playlists.len();
        
        let paginated_tracks = found_tracks.into_iter()
            .skip(offset)
            .take(limit)
            .collect();
            
        let paginated_albums = found_albums.into_iter()
            .skip(offset)
            .take(limit)
            .collect();

        let paginated_playlists = found_playlists.into_iter()
            .skip(offset)
            .take(limit)
            .collect();
        
        Ok(SearchResults {
            tracks: paginated_tracks,
            albums: paginated_albums,
            playlists: paginated_playlists,
            total: (total_tracks + total_albums + total_playlists) as u32,
            offset: offset as u32,
            limit: limit as u32,
        })
    }

    async fn search_playlists(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<StreamingPlaylist>> {
        let playlists = self.scan_playlists().await.map_err(|e| anyhow!(e))?;
        let found_playlists = self.search_playlists(&playlists, query);
        
        let limit = limit.unwrap_or(20) as usize;
        let offset = offset.unwrap_or(0) as usize;
        
        let paginated_playlists = found_playlists.into_iter()
            .skip(offset)
            .take(limit)
            .collect();
        
        Ok(paginated_playlists)
    }

    async fn get_playlist_tracks(&self, playlist_id: &str, limit: Option<u32>, offset: Option<u32>) -> Result<Vec<StreamingTrack>> {
        // Parse playlist_id format: "server_playlist_{path}"
        if let Some(playlist_part) = playlist_id.strip_prefix("server_playlist_") {
            let decoded_path = urlencoding::decode(playlist_part)
                .map_err(|e| anyhow!("Failed to decode playlist path: {}", e))?;
            
            let playlist_path = self.music_dir.join(decoded_path.as_ref());
            
            if playlist_path.exists() && playlist_path.is_dir() {
                let mut tracks = self.get_playlist_tracks_by_path(&playlist_path).await?;
                
                let limit = limit.unwrap_or(50) as usize;
                let offset = offset.unwrap_or(0) as usize;
                
                // Apply pagination
                tracks = tracks.into_iter()
                    .skip(offset)
                    .take(limit)
                    .collect();
                
                return Ok(tracks);
            }
        }
        
        Err(anyhow!("Invalid playlist ID format for server source"))
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
                
                let mut album_tracks: Vec<StreamingTrack> = all_tracks.iter()
                    .filter(|track| track.artist == artist && track.album == album)
                    .map(|track| StreamingTrack {
                        id: format!("server_{}", track.file_path.to_string_lossy()),
                        title: track.title.clone(),
                        artist: track.artist.clone(),
                        album: track.album.clone(),
                        duration: track.duration.map(|d| d as i32),
                        stream_url: Some(self.get_stream_url_for_track(track)),
                        cover_url: track.cover_url.clone(),
                        source: "server".to_string(),
                        quality: Some("Original".to_string()),
                        bitrate: None,
                        sample_rate: None,
                        bit_depth: None,
                    })
                    .collect();
                
                // Sort tracks by track number if available, otherwise by filename
                album_tracks.sort_by(|a, b| {
                    let track_a = all_tracks.iter().find(|t| format!("server_{}", t.file_path.to_string_lossy()) == a.id);
                    let track_b = all_tracks.iter().find(|t| format!("server_{}", t.file_path.to_string_lossy()) == b.id);
                    
                    match (track_a.and_then(|t| t.track_number), track_b.and_then(|t| t.track_number)) {
                        (Some(a_num), Some(b_num)) => a_num.cmp(&b_num),
                        (Some(_), None) => std::cmp::Ordering::Less,
                        (None, Some(_)) => std::cmp::Ordering::Greater,
                        (None, None) => a.title.cmp(&b.title),
                    }
                });
                
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

    async fn search_library(&self, query: &str, search_type: Option<&str>, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults> {
        // For local server, library search is the same as regular search since all files are "in the library"
        self.search(query, limit, offset).await
    }
}
