pub mod qobuz;
pub mod spotify;
pub mod local;
pub mod interface;

pub use interface::*;
pub use qobuz::*;
pub use spotify::*;
pub use local::*;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamingTrack {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: Option<i32>,
    pub stream_url: Option<String>,
    pub cover_url: Option<String>,
    pub quality: Option<String>,
    pub source: String,
    pub bitrate: Option<i32>,      // in kbps
    pub sample_rate: Option<i32>,  // in Hz
    pub bit_depth: Option<i32>,    // in bits
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamingAlbum {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub release_date: Option<String>,
    pub cover_url: Option<String>,
    pub tracks: Vec<StreamingTrack>,
    pub source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamingPlaylist {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub owner: String,
    pub source: String,
    pub cover_url: Option<String>,
    pub track_count: u32,
    pub is_public: bool,
    pub external_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResults {
    pub tracks: Vec<StreamingTrack>,
    pub albums: Vec<StreamingAlbum>,
    pub playlists: Vec<StreamingPlaylist>,
    pub total: u32,
    pub offset: u32,
    pub limit: u32,
}
