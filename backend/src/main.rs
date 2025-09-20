mod models;
mod services;
mod handlers;
mod migrator;

use anyhow::Result;
use axum::{
    http::Method,
    middleware,
    routing::{get, post, delete, put},
    Router,
};
use dotenvy::dotenv;
use sea_orm::{Database, DatabaseConnection};
use sea_orm_migration::prelude::*;
use std::env;
use tower::ServiceBuilder;
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, error};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use handlers::auth::{AppState, auth_middleware, register, login, logout, me};
use handlers::streaming::{search_music, get_stream_url, get_backend_stream_url, connect_qobuz, connect_spotify, get_available_services, get_service_status, disconnect_service, get_spotify_auth_url, spotify_callback, transfer_spotify_playback, get_spotify_access_token, refresh_spotify_token};
use handlers::music::{get_user_playlists, create_playlist, get_playlist};
use handlers::playlist::{get_playlists, create_playlist as create_new_playlist, get_playlist as get_new_playlist, update_playlist, delete_playlist, get_playlist_items, add_playlist_item, remove_playlist_item, reorder_playlist_item};
use handlers::saved_tracks::{save_track, get_saved_tracks, remove_saved_track, is_track_saved};
use handlers::queue::{get_queue, add_to_queue, remove_from_queue, reorder_queue, clear_queue};
use services::{AuthService, streaming_service::StreamingService};
use std::sync::Arc;
use migrator::Migrator;

#[tokio::main]
async fn main() -> Result<()> {
    // Load environment variables
    dotenv().ok();

    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Database connection
    let database_url = env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set");
    
    info!("Connecting to database: {}", database_url);
    let db = Database::connect(&database_url).await?;
    
    // Run migrations
    info!("Running database migrations...");
    Migrator::up(&db, None).await?;
    info!("Database migrations completed successfully");
    
    // Create services
    let auth_service = AuthService::new(db.clone());
    
    // Create streaming service
    let cache_dir = std::path::PathBuf::from("./cache");
    let streaming_service = Arc::new(StreamingService::new(cache_dir));
    streaming_service.initialize().await?;
    
    // Application state
    let app_state = AppState {
        auth_service,
        streaming_service: streaming_service.clone(),
    };

    // CORS configuration
    let cors = CorsLayer::new()
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers(Any)
        .allow_origin(Any);

    // Build protected routes with authentication middleware
    let protected_routes = Router::new()
        .route("/api/auth/logout", post(logout))
        .route("/api/auth/me", get(me))
        .route("/api/streaming/search", get(search_music))
        .route("/api/streaming/stream-url", get(get_stream_url))
        .route("/api/streaming/backend-stream-url", get(get_backend_stream_url))
        .route("/api/streaming/services", get(get_available_services))
        .route("/api/streaming/status", get(get_service_status))
        .route("/api/streaming/connect/qobuz", post(connect_qobuz))
        .route("/api/streaming/connect/spotify", post(connect_spotify))
        .route("/api/streaming/spotify/auth-url", get(get_spotify_auth_url))
        .route("/api/streaming/spotify/transfer", post(transfer_spotify_playback))
        .route("/api/streaming/spotify/token", get(get_spotify_access_token))
        .route("/api/streaming/spotify/refresh", post(refresh_spotify_token))
        .route("/api/streaming/disconnect", post(disconnect_service))
        .route("/api/playlists", get(get_user_playlists))
        .route("/api/playlists", post(create_playlist))
        .route("/api/playlists/{id}", get(get_playlist))
        // New playlist system
        .route("/api/v2/playlists", get(get_playlists))
        .route("/api/v2/playlists", post(create_new_playlist))
        .route("/api/v2/playlists/{id}", get(get_new_playlist))
        .route("/api/v2/playlists/{id}", put(update_playlist))
        .route("/api/v2/playlists/{id}", delete(delete_playlist))
        .route("/api/v2/playlists/{id}/items", get(get_playlist_items))
        .route("/api/v2/playlists/{id}/items", post(add_playlist_item))
        .route("/api/v2/playlists/{playlist_id}/items/{item_id}", delete(remove_playlist_item))
        .route("/api/v2/playlists/{playlist_id}/items/{item_id}/reorder", put(reorder_playlist_item))
        .route("/api/saved-tracks", get(get_saved_tracks))
        .route("/api/saved-tracks", post(save_track))
        .route("/api/saved-tracks/{id}", delete(remove_saved_track))
        .route("/api/saved-tracks/check", get(is_track_saved))
        .route("/api/queue", get(get_queue))
        .route("/api/queue", post(add_to_queue))
        .route("/api/queue", delete(clear_queue))
        .route("/api/queue/{id}", delete(remove_from_queue))
        .route("/api/queue/{id}/reorder", put(reorder_queue))
        .layer(
            ServiceBuilder::new()
                .layer(middleware::from_fn_with_state(
                    app_state.clone(),
                    auth_middleware,
                ))
        );

    // Build the application with routes
    let app = Router::new()
        // Public routes
        .route("/api/auth/register", post(register))
        .route("/api/auth/login", post(login))
        .route("/api/streaming/spotify/callback", get(spotify_callback))
        .route("/health", get(health_check))
        // Streaming service routes (public for audio streaming)
        .merge(StreamingService::router(streaming_service))
        // Merge protected routes
        .merge(protected_routes)
        
        // Apply CORS and state
        .layer(cors)
        .with_state(app_state);

    // Start server
    let host = env::var("SERVER_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
    let port = env::var("SERVER_PORT").unwrap_or_else(|_| "8080".to_string());
    let address = format!("{}:{}", host, port);

    info!("🚀 Musestruct backend starting on {}", address);
    
    let listener = tokio::net::TcpListener::bind(&address).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> &'static str {
    "OK"
}
