mod models;
mod services;
mod handlers;
mod migrator;

use anyhow::Result;
use axum::{
    http::Method,
    middleware,
    routing::{get, post},
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
use handlers::streaming::{search_music, get_stream_url, connect_qobuz, connect_spotify, get_available_services};
use handlers::music::{get_user_playlists, create_playlist, get_playlist};
use services::AuthService;
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
    
    // Application state
    let app_state = AppState {
        auth_service,
    };

    // CORS configuration
    let cors = CorsLayer::new()
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers(Any)
        .allow_origin(Any);

    // Build the application with routes
    let app = Router::new()
        // Public routes
        .route("/api/auth/register", post(register))
        .route("/api/auth/login", post(login))
        
        // Protected routes
        .route("/api/auth/logout", post(logout))
        .route("/api/auth/me", get(me))
        .route("/api/streaming/search", get(search_music))
        .route("/api/streaming/stream-url", get(get_stream_url))
        .route("/api/streaming/services", get(get_available_services))
        .route("/api/streaming/connect/qobuz", post(connect_qobuz))
        .route("/api/streaming/connect/spotify", post(connect_spotify))
        .route("/api/playlists", get(get_user_playlists))
        .route("/api/playlists", post(create_playlist))
        .route("/api/playlists/{id}", get(get_playlist))
        .layer(
            ServiceBuilder::new()
                .layer(middleware::from_fn_with_state(
                    app_state.clone(),
                    auth_middleware,
                ))
        )
        
        // Health check route (public)
        .route("/health", get(health_check))
        
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
