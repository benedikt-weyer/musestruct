use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use sea_orm::{EntityTrait, ColumnTrait, QueryFilter, Set, ActiveModelTrait};

use crate::handlers::auth::{AppState, ApiResponse};
use crate::services::{SpectrogramBpmAnalysisService, KeyAnalysisService};
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

#[derive(Serialize)]
pub struct SpectrogramBpmAnalysisResponse {
    pub track_id: String,
    pub source: String,
    pub bpm: f32,
    pub analysis_time_ms: u64,
    pub spectrogram_path: String,
    pub analysis_visualization_path: String,
}

#[derive(Deserialize)]
pub struct AnalyzeKeyQuery {
    pub track_id: String,
    pub source: String,
    pub stream_url: Option<String>,
}

#[derive(Serialize)]
pub struct KeyAnalysisResponse {
    pub track_id: String,
    pub source: String,
    pub key_name: String,
    pub camelot: String,
    pub confidence: f32,
    pub is_major: bool,
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

    // Create spectrogram analysis service (now the only BPM analysis method)
    let analysis_service = SpectrogramBpmAnalysisService::new();

    // Analyze BPM using spectrogram approach
    let track_id = query.track_id.clone();
    let source = query.source.clone();
    
    tracing::info!("Starting spectrogram BPM analysis task for track: {} ({})", track_id, source);
    
    let bpm = if stream_url.starts_with("http://") || stream_url.starts_with("https://") {
        tracing::debug!("Analyzing remote file with spectrogram: {}", stream_url);
        match analysis_service.analyze_remote_file_spectrogram(&stream_url).await {
            Ok((bpm, _, _)) => {
                tracing::info!("Remote spectrogram analysis successful: {} BPM", bpm);
                bpm
            },
            Err(e) => {
                tracing::error!("Remote spectrogram analysis failed for {}: {}", stream_url, e);
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!("BPM analysis failed: {}", e))),
                ));
            }
        }
    } else {
        tracing::debug!("Analyzing local file with spectrogram: {}", stream_url);
        match analysis_service.analyze_bpm_with_spectrogram(&stream_url).await {
            Ok((bpm, _, _)) => {
                tracing::info!("Spectrogram analysis successful: {} BPM", bpm);
                bpm
            },
            Err(e) => {
                tracing::error!("Spectrogram analysis failed for {}: {}", stream_url, e);
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!("BPM analysis failed: {}", e))),
                ));
            }
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

/// Analyze BPM using spectrogram approach and save spectrogram image
pub async fn analyze_track_bpm_spectrogram(
    State(state): State<AppState>,
    Query(query): Query<AnalyzeBpmQuery>,
) -> Result<Json<ApiResponse<SpectrogramBpmAnalysisResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let start_time = std::time::Instant::now();
    
    tracing::info!("=== SPECTROGRAM BPM ANALYSIS ENDPOINT CALLED ===");
    tracing::info!("Spectrogram BPM analysis request - Track ID: {}, Source: {}, Stream URL: {:?}", 
                   query.track_id, query.source, query.stream_url);
    
    // Get the stream URL for the track
    let stream_url = match query.stream_url {
        Some(url) => {
            tracing::debug!("Using provided stream URL: {}", url);
            url
        },
        None => {
            tracing::debug!("No stream URL provided, attempting to resolve for source: {}", query.source);
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

    // Create spectrogram analysis service
    let analysis_service = SpectrogramBpmAnalysisService::new();

    // Analyze BPM with spectrogram
    let track_id = query.track_id.clone();
    let source = query.source.clone();
    
    tracing::info!("Starting spectrogram BPM analysis task for track: {} ({})", track_id, source);
    
    let (bpm, spectrogram_path, analysis_visualization_path) = if stream_url.starts_with("http://") || stream_url.starts_with("https://") {
        tracing::debug!("Analyzing remote file with spectrogram: {}", stream_url);
        match analysis_service.analyze_remote_file_spectrogram(&stream_url).await {
            Ok((bpm, spec_path, viz_path)) => {
                tracing::info!("Remote spectrogram analysis successful: {} BPM, spectrogram: {}, visualization: {}", bpm, spec_path, viz_path);
                (bpm, spec_path, viz_path)
            },
            Err(e) => {
                tracing::error!("Remote spectrogram analysis failed for {}: {}", stream_url, e);
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!("Remote spectrogram analysis failed: {}", e))),
                ));
            }
        }
    } else {
        tracing::debug!("Analyzing local file with spectrogram: {}", stream_url);
        match analysis_service.analyze_bpm_with_spectrogram(&stream_url).await {
            Ok((bpm, spec_path, viz_path)) => {
                tracing::info!("Spectrogram analysis successful: {} BPM, spectrogram: {}, visualization: {}", bpm, spec_path, viz_path);
                (bpm, spec_path, viz_path)
            },
            Err(e) => {
                tracing::error!("Spectrogram analysis failed for {}: {}", stream_url, e);
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!("Spectrogram analysis failed: {}", e))),
                ));
            }
        }
    };

    let analysis_duration = start_time.elapsed();
    
    // Save BPM to database
    let db = state.db();
    
    // Find existing saved track or create new one
    let existing_track = SavedTrack::find()
        .filter(crate::models::saved_track::Column::TrackId.eq(&track_id))
        .filter(crate::models::saved_track::Column::Source.eq(&source))
        .one(db)
        .await
        .map_err(|e| {
            tracing::error!("Database error when finding saved track: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error("Database error".to_string())),
            )
        })?;

    match existing_track {
        Some(track) => {
            // Update existing track
            let mut active_track: SavedTrackActiveModel = track.into();
            active_track.bpm = Set(Some(bpm));
            
            active_track.update(db).await.map_err(|e| {
                tracing::error!("Failed to update track BPM in database: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error("Failed to save BPM".to_string())),
                )
            })?;
            
            tracing::info!("Updated existing track {} ({}) with BPM: {}", track_id, source, bpm);
        }
        None => {
            // Create new saved track entry
            let new_track = SavedTrackActiveModel {
                track_id: Set(track_id.clone()),
                source: Set(source.clone()),
                bpm: Set(Some(bpm)),
                ..Default::default()
            };
            
            new_track.insert(db).await.map_err(|e| {
                tracing::error!("Failed to insert new track with BPM: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error("Failed to save BPM".to_string())),
                )
            })?;
            
            tracing::info!("Created new track entry {} ({}) with BPM: {}", track_id, source, bpm);
        }
    }

    let response = SpectrogramBpmAnalysisResponse {
        track_id,
        source,
        bpm,
        analysis_time_ms: analysis_duration.as_millis() as u64,
        spectrogram_path,
        analysis_visualization_path,
    };

    tracing::info!("Spectrogram BPM analysis completed successfully: {} BPM in {}ms", 
                   bpm, analysis_duration.as_millis());

    Ok(Json(ApiResponse::success(response)))
}

/// Analyze key of a track and save it to the database
pub async fn analyze_track_key(
    State(state): State<AppState>,
    Query(query): Query<AnalyzeKeyQuery>,
) -> Result<Json<ApiResponse<KeyAnalysisResponse>>, (StatusCode, Json<ApiResponse<()>>)> {
    let start_time = std::time::Instant::now();
    
    tracing::info!("Starting key analysis for track: {} ({})", query.track_id, query.source);
    
    // Get stream URL from query or fetch it
    let stream_url = match query.stream_url {
        Some(url) => url,
        None => {
            tracing::error!("No stream URL provided for key analysis");
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ApiResponse::<()>::error("Stream URL is required for key analysis".to_string())),
            ));
        }
    };

    // Create key analysis service
    let analysis_service = KeyAnalysisService::new();
    
    let track_id = query.track_id.clone();
    let source = query.source.clone();
    
    tracing::info!("Starting key analysis task for track: {} ({})", track_id, source);
    
    let key_result = if stream_url.starts_with("http://") || stream_url.starts_with("https://") {
        tracing::debug!("Analyzing remote file for key: {}", stream_url);
        match analysis_service.analyze_remote_file_key(&stream_url).await {
            Ok(key) => {
                tracing::info!("Remote key analysis successful: {} ({}), confidence: {:.3}", 
                              key.key_name, key.camelot, key.confidence);
                key
            },
            Err(e) => {
                tracing::error!("Remote key analysis failed for {}: {}", stream_url, e);
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!("Remote key analysis failed: {}", e))),
                ));
            }
        }
    } else {
        tracing::debug!("Analyzing local file for key: {}", stream_url);
        match analysis_service.analyze_key(&stream_url).await {
            Ok(key) => {
                tracing::info!("Key analysis successful: {} ({}), confidence: {:.3}", 
                              key.key_name, key.camelot, key.confidence);
                key
            },
            Err(e) => {
                tracing::error!("Key analysis failed for {}: {}", stream_url, e);
                return Err((
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ApiResponse::<()>::error(format!("Key analysis failed: {}", e))),
                ));
            }
        }
    };

    let analysis_duration = start_time.elapsed();
    
    // Save key to database (update existing saved track if it exists)
    let db = state.db();
    
    // Find existing saved track
    let existing_track = SavedTrack::find()
        .filter(crate::models::saved_track::Column::TrackId.eq(&track_id))
        .filter(crate::models::saved_track::Column::Source.eq(&source))
        .one(db)
        .await
        .map_err(|e| {
            tracing::error!("Database error when finding saved track: {}", e);
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(ApiResponse::<()>::error("Database error".to_string())),
            )
        })?;

    if let Some(track) = existing_track {
        // Update existing track with key information
        let mut track_update: SavedTrackActiveModel = track.into();
        track_update.key_name = Set(Some(key_result.key_name.clone()));
        track_update.camelot = Set(Some(key_result.camelot.clone()));
        track_update.key_confidence = Set(Some(key_result.confidence));
        
        match track_update.update(db).await {
            Ok(_) => {
                tracing::info!("Updated existing saved track {} with key: {} ({})", 
                              track_id, key_result.key_name, key_result.camelot);
            }
            Err(e) => {
                tracing::error!("Failed to update saved track with key: {}", e);
            }
        }
    } else {
        tracing::debug!("No existing saved track found for key update: {} ({})", track_id, source);
    }

    let response = KeyAnalysisResponse {
        track_id,
        source,
        key_name: key_result.key_name,
        camelot: key_result.camelot,
        confidence: key_result.confidence,
        is_major: key_result.is_major,
        analysis_time_ms: analysis_duration.as_millis() as u64,
    };

    tracing::info!("Key analysis completed successfully: {} ({}) with confidence {:.3} in {}ms", 
                   response.key_name, response.camelot, response.confidence, analysis_duration.as_millis());

    Ok(Json(ApiResponse::success(response)))
}

