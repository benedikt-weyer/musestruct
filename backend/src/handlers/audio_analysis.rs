use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sea_orm::{EntityTrait, ColumnTrait, QueryFilter, Set, ActiveModelTrait};

use crate::handlers::auth::{AppState, ApiResponse};
use crate::services::AudioAnalysisService;
use crate::models::saved_track::{Entity as SavedTrack, ActiveModel as SavedTrackActiveModel};

#[derive(Deserialize)]
pub struct AnalyzeBpmQuery {
    pub track_id: String,
    pub source: String,
    pub stream_url: Option<String>,
}

#[derive(Serialize)]
pub struct BpmAnalysisResponse {
    pub track_id: String,
    pub source: String,
    pub bpm: f32,
    pub analysis_time_ms: u64,
}

/// Analyze BPM of a track and save it to the database
pub async fn analyze_track_bpm(
    State(state): State<AppState>,
    Query(query): Query<AnalyzeBpmQuery>,
) -> Result<Json<ApiResponse<BpmAnalysisResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let start_time = std::time::Instant::now();
    
    // Log at ERROR level to ensure it shows up
    tracing::error!("=== BPM ANALYSIS ENDPOINT CALLED ===");
    tracing::error!("BPM analysis request received - Track ID: {}, Source: {}, Stream URL: {:?}", 
                   query.track_id, query.source, query.stream_url);
    println!("=== BPM ANALYSIS ENDPOINT CALLED ===");
    println!("BPM analysis request received - Track ID: {}, Source: {}, Stream URL: {:?}", 
             query.track_id, query.source, query.stream_url);
    
    // Get the stream URL for the track
    let stream_url = match query.stream_url {
        Some(url) => {
            tracing::debug!("Using provided stream URL: {}", url);
            url
        },
        None => {
            tracing::debug!("No stream URL provided, attempting to resolve for source: {}", query.source);
            // Try to get stream URL from streaming service
            match get_stream_url_for_track(&state, &query.track_id, &query.source).await {
                Ok(url) => {
                    tracing::debug!("Resolved stream URL: {}", url);
                    url
                },
                Err(e) => {
                    tracing::error!("Failed to get stream URL for track {} ({}): {}", 
                                   query.track_id, query.source, e);
                    return Err((
                        StatusCode::BAD_REQUEST,
                        Json(ApiResponse::<()>::error(format!("Could not get stream URL: {}", e))),
                    ));
                }
            }
        }
    };

    // Create audio analysis service
    let analysis_service = AudioAnalysisService::new();

    // Analyze BPM in a separate task to avoid blocking
    let track_id = query.track_id.clone();
    let source = query.source.clone();
    
    tracing::info!("Starting BPM analysis task for track: {} ({})", track_id, source);
    
    let bpm_result = tokio::spawn(async move {
        tracing::debug!("BPM analysis task started with URL: {}", stream_url);
        
        let result = if stream_url.starts_with("http://") || stream_url.starts_with("https://") {
            tracing::debug!("Analyzing remote file: {}", stream_url);
            match analysis_service.analyze_remote_file(&stream_url).await {
                Ok(bpm) => {
                    tracing::info!("Remote file analysis successful: {} BPM", bpm);
                    Ok(bpm)
                },
                Err(e) => {
                    tracing::error!("Remote file analysis failed for {}: {}", stream_url, e);
                    Err(e)
                }
            }
        } else {
            tracing::debug!("Analyzing local file: {}", stream_url);
            match analysis_service.analyze_bpm(&stream_url).await {
                Ok(bpm) => {
                    tracing::info!("Local file analysis successful: {} BPM", bpm);
                    Ok(bpm)
                },
                Err(e) => {
                    tracing::error!("Local file analysis failed for {}: {}", stream_url, e);
                    Err(e)
                }
            }
        };
        
        tracing::debug!("BPM analysis task completed with result: {:?}", result);
        result
    }).await;

    let bpm = match bpm_result {
        Ok(Ok(bpm)) => bpm,
        Ok(Err(e)) => {
            tracing::error!("BPM analysis failed for track {}: {}", query.track_id, e);
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error(format!("BPM analysis failed: {}", e))),
            ));
        }
        Err(e) => {
            tracing::error!("BPM analysis task failed for track {}: {}", query.track_id, e);
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error("BPM analysis task failed".to_string())),
            ));
        }
    };

    // Update all saved tracks with this track_id and source to include the BPM
    let db = state.db();
    
    tracing::debug!("Searching for saved tracks to update with BPM - Track ID: {}, Source: {}", 
                    query.track_id, query.source);
    
    let saved_tracks = SavedTrack::find()
        .filter(crate::models::saved_track::Column::TrackId.eq(&query.track_id))
        .filter(crate::models::saved_track::Column::Source.eq(&query.source))
        .all(db)
        .await
        .map_err(|e| {
            tracing::error!("Database error when finding saved tracks: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error("Database error".to_string())),
            )
        })?;

    tracing::info!("Found {} saved tracks to update with BPM: {}", saved_tracks.len(), bpm);

    // Update each saved track with the BPM
    let mut updated_count = 0;
    for saved_track in saved_tracks {
        let track_uuid = saved_track.id;
        let mut active_model: SavedTrackActiveModel = saved_track.into();
        active_model.bpm = Set(Some(bpm));
        
        match active_model.update(db).await {
            Ok(_) => {
                updated_count += 1;
                tracing::debug!("Updated saved track {} with BPM: {}", track_uuid, bpm);
            },
            Err(e) => {
                tracing::error!("Failed to update saved track {} with BPM: {}", track_uuid, e);
                // Continue with other tracks even if one fails
            }
        }
    }
    
    tracing::info!("Successfully updated {} saved tracks with BPM: {}", updated_count, bpm);

    let analysis_time = start_time.elapsed();
    
    let response = BpmAnalysisResponse {
        track_id: query.track_id,
        source: query.source,
        bpm,
        analysis_time_ms: analysis_time.as_millis() as u64,
    };

    tracing::info!("BPM analysis completed for track {} ({}): {} BPM in {}ms", 
                   response.track_id, response.source, response.bpm, response.analysis_time_ms);

    Ok(Json(ApiResponse::success(response)))
}

/// Helper function to get stream URL for a track
async fn get_stream_url_for_track(
    _state: &AppState,
    track_id: &str,
    source: &str,
) -> Result<String, String> {
    tracing::debug!("Resolving stream URL for track_id: {}, source: {}", track_id, source);
    
    let result = match source.to_lowercase().as_str() {
        "local" => {
            // For local files, the track_id might be the file path
            // Check if it's already a full path or needs to be constructed
            if track_id.starts_with('/') || track_id.starts_with("file://") {
                tracing::debug!("Using absolute path for local file: {}", track_id);
                // Check if file exists
                let path = if track_id.starts_with("file://") {
                    &track_id[7..]
                } else {
                    track_id
                };
                if std::path::Path::new(path).exists() {
                    Ok(track_id.to_string())
                } else {
                    let error_msg = format!("Local file not found: {}", path);
                    tracing::error!("{}", error_msg);
                    Err(error_msg)
                }
            } else {
                // Construct path relative to music directory
                let path = format!("./own_music/{}", track_id);
                tracing::debug!("Constructed local file path: {}", path);
                if std::path::Path::new(&path).exists() {
                    Ok(path)
                } else {
                    let error_msg = format!("Local file not found: {}", path);
                    tracing::error!("{}", error_msg);
                    Err(error_msg)
                }
            }
        }
        "server" => {
            // For server files, construct the local path
            let path = format!("./cache/{}", track_id);
            tracing::debug!("Constructed server cache path: {}", path);
            if std::path::Path::new(&path).exists() {
                Ok(path)
            } else {
                let error_msg = format!("Cached file not found: {}. The track may need to be played first to cache it.", path);
                tracing::error!("{}", error_msg);
                Err(error_msg)
            }
        }
        "spotify" | "qobuz" | "tidal" => {
            // For streaming services, we would need to get a downloadable URL
            // This is complex and would require service-specific implementation
            // For now, we'll return an error but suggest using cached files
            let error_msg = format!("BPM analysis for {} tracks requires downloading the track first. Try playing the track to cache it, then analyze.", source);
            tracing::warn!("Stream URL resolution failed for streaming service: {}", error_msg);
            Err(error_msg)
        }
        _ => {
            let error_msg = format!("Unsupported source for BPM analysis: {}", source);
            tracing::error!("Unsupported source type: {}", source);
            Err(error_msg)
        }
    };
    
    match &result {
        Ok(url) => tracing::debug!("Stream URL resolved successfully: {}", url),
        Err(e) => tracing::debug!("Stream URL resolution failed: {}", e),
    }
    
    result
}

#[derive(Deserialize)]
pub struct GetBpmQuery {
    pub track_id: String,
    pub source: String,
}

#[derive(Serialize)]
pub struct BpmResponse {
    pub track_id: String,
    pub source: String,
    pub bpm: Option<f32>,
}

/// Get the BPM for a track if it has been analyzed
pub async fn get_track_bpm(
    State(state): State<AppState>,
    Query(query): Query<GetBpmQuery>,
) -> Result<Json<ApiResponse<BpmResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let db = state.db();
    
    let saved_track = SavedTrack::find()
        .filter(crate::models::saved_track::Column::TrackId.eq(&query.track_id))
        .filter(crate::models::saved_track::Column::Source.eq(&query.source))
        .one(db)
        .await
        .map_err(|e| {
            tracing::error!("Database error when finding saved track: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error("Database error".to_string())),
            )
        })?;

    let bpm = saved_track.and_then(|track| track.bpm);
    
    let response = BpmResponse {
        track_id: query.track_id,
        source: query.source,
        bpm,
    };

    Ok(Json(ApiResponse::success(response)))
}

