pub mod qobuz;
pub mod spotify;
pub mod interface;

pub use interface::*;
pub use qobuz::*;
pub use spotify::*;

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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamingAlbum {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub release_date: Option<String>,
    pub cover_url: Option<String>,
    pub tracks: Vec<StreamingTrack>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResults {
    pub tracks: Vec<StreamingTrack>,
    pub albums: Vec<StreamingAlbum>,
    pub total: u32,
    pub offset: u32,
    pub limit: u32,
}
