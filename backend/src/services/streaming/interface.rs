use async_trait::async_trait;
use anyhow::Result;
use super::{SearchResults, StreamingTrack};

#[async_trait]
pub trait StreamingService: Send + Sync {
    /// Search for tracks across the streaming service
    async fn search(&self, query: &str, limit: Option<u32>, offset: Option<u32>) -> Result<SearchResults>;
    
    /// Get stream URL for a track
    async fn get_stream_url(&self, track_id: &str, quality: Option<&str>) -> Result<String>;
    
    /// Get track details by ID
    async fn get_track(&self, track_id: &str) -> Result<StreamingTrack>;
    
    /// Authenticate user with the service
    async fn authenticate(&self, credentials: &ServiceCredentials) -> Result<AuthResult>;
    
    /// Check if the service is available and authenticated
    async fn is_authenticated(&self) -> bool;
    
    /// Get service name
    fn service_name(&self) -> &str;
}

#[derive(Debug, Clone)]
pub struct ServiceCredentials {
    pub username: Option<String>,
    pub password: Option<String>,
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub app_id: Option<String>,
    pub secret: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AuthResult {
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
    pub user_id: Option<String>,
}

pub type DynStreamingService = Box<dyn StreamingService>;
