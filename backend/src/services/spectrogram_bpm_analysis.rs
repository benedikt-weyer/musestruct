use anyhow::{Result, anyhow};
use std::path::Path;
use tokio::task;
use hound::Error as HoundError;
use symphonia::core::audio::AudioBufferRef;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use std::fs::File;
use spectrum_analyzer::{samples_fft_to_spectrum, FrequencyLimit};
use spectrum_analyzer::windows::hann_window;
use spectrum_analyzer::scaling::divide_by_N_sqrt;
use image::{ImageBuffer, Rgb, RgbImage};

// Additional imports for remote file support
use uuid;
use reqwest;

// Analysis configuration for spectrogram approach
const SPECTROGRAM_WINDOW_SIZE: usize = 4096; // Larger window for better frequency resolution
const SPECTROGRAM_HOP_SIZE: usize = 256; // 4x more precise time resolution (was 1024)
const SAMPLE_RATE: u32 = 44100;
const LOW_FREQ_CUTOFF: f32 = 10.0; // Slightly higher for beat detection
const HIGH_FREQ_CUTOFF: f32 = 2000.0; // Upper limit for beat-relevant frequencies
const ADAPTIVE_THRESHOLD_PERCENTAGE: f32 = 0.8; // 80% of energy range: min + (max-min) * 80%

// BPM calculation configuration
const SCORE_DEVIATION_PERCENTAGE: f32 = 0.1; // 10% deviation from max score for averaging candidates
const USE_WEIGHTED_AVERAGING: bool = true; // If true, average weighted by score; if false, unweighted average

/// Represents the full spectrogram of a song
#[derive(Debug)]
struct Spectrogram {
    data: Vec<Vec<f32>>, // [time_frame][frequency_bin]
    time_resolution: f32, // Time per frame in seconds
    freq_resolution: f32, // Frequency per bin in Hz
    min_freq: f32,
    max_freq: f32,
    duration: f32,
}

/// Detected beat with enhanced information
#[derive(Debug, Clone)]
struct SpectrogramBeat {
    timestamp: f32,
    energy: f32,
    dominant_freq: f32, // Dominant frequency at this beat
    confidence: f32,    // Beat detection confidence
}

/// Cached analysis data to avoid recalculation in visualization
#[derive(Debug, Clone)]
struct AnalysisCache {
    frame_energies: Vec<(usize, f32, f32)>, // (frame_idx, timestamp, avg_energy)
    section_thresholds: Vec<(usize, usize, f32)>, // (section_start, section_end, threshold)
    energy_groups: Vec<Vec<(usize, f32, f32, f32, f32)>>, // groups of (frame_idx, timestamp, energy, dominant_freq, threshold)
    max_energy: f32,
}

/// Audio track structure (reused from main service)
struct AudioTrack {
    pub samples: Vec<f32>,
    pub sample_rate: u32,
}

pub struct SpectrogramBpmAnalysisService;

impl SpectrogramBpmAnalysisService {
    pub fn new() -> Self {
        Self
    }

    /// Analyze BPM using full-song spectrogram approach
    pub async fn analyze_bpm_with_spectrogram(&self, file_path: &str) -> Result<(f32, String, String)> {
        tracing::info!("Starting spectrogram-based BPM analysis for file: {}", file_path);
        let start_time = std::time::Instant::now();
        let file_path_owned = file_path.to_string();
        let file_path_for_logging = file_path_owned.clone();
        
        // Run the analysis in a blocking task
        let (bpm, spectrogram_path, visualization_path) = task::spawn_blocking(move || {
            Self::analyze_bpm_spectrogram_blocking(&file_path_owned)
        }).await??;

        let analysis_duration = start_time.elapsed();
        tracing::info!("Spectrogram BPM analysis completed for file: {} - Result: {} BPM - Duration: {:?}", 
                       file_path_for_logging, bpm, analysis_duration);

        Ok((bpm, spectrogram_path, visualization_path))
    }

    /// Blocking spectrogram-based BPM analysis
    fn analyze_bpm_spectrogram_blocking(file_path: &str) -> Result<(f32, String, String)> {
        tracing::debug!("Reading audio file for spectrogram analysis: {}", file_path);
        
        // Check if file exists
        if !Path::new(file_path).exists() {
            tracing::error!("Audio file not found: {}", file_path);
            return Err(anyhow!("Audio file not found: {}", file_path));
        }

        // Step 1: Read audio file
        let track = Self::read_audio_file(file_path)?;
        tracing::info!("Audio loaded - Sample rate: {} Hz, Samples: {}, Duration: {:.2}s", 
                       track.sample_rate, track.samples.len(), 
                       track.samples.len() as f32 / track.sample_rate as f32);
        
        // Step 2: Generate full-song spectrogram
        tracing::debug!("Generating full-song spectrogram...");
        let spectrogram = Self::generate_spectrogram(&track.samples, track.sample_rate)?;
        tracing::info!("Spectrogram generated - Size: {}x{} (time x freq), Duration: {:.2}s", 
                       spectrogram.data.len(), 
                       spectrogram.data.first().map_or(0, |f| f.len()),
                       spectrogram.duration);
        
        // Step 3: Save spectrogram as image
        let spectrogram_path = Self::save_spectrogram_image(&spectrogram, file_path)?;
        tracing::info!("Spectrogram image saved to: {}", spectrogram_path);
        
        // Step 4: Detect beats from spectrogram
        tracing::debug!("Detecting beats from spectrogram...");
        let (beats, analysis_cache) = Self::detect_beats_from_spectrogram(&spectrogram)?;
        tracing::info!("Beat detection completed - Found {} beats", beats.len());
        
        if beats.len() < 3 {
            tracing::warn!("Not enough beats detected for BPM calculation, using default");
            // Still create visualization even with few beats
            let visualization_path = Self::create_analysis_visualization(&beats, &spectrogram, &analysis_cache, file_path, 120.0)?;
            return Ok((120.0, spectrogram_path, visualization_path));
        }
        
        // Step 5: Calculate BPM using histogram-based interval analysis
        tracing::debug!("Calculating BPM using histogram analysis...");
        let bpm = Self::calculate_bpm_histogram(&beats)?;
        tracing::debug!("Histogram BPM calculation result: {:.1}", bpm);
        
        // Step 6: Create analysis visualization
        tracing::debug!("Creating analysis visualization...");
        let visualization_path = Self::create_analysis_visualization(&beats, &spectrogram, &analysis_cache, file_path, bpm)?;
        tracing::info!("Analysis visualization saved to: {}", visualization_path);
        
        // Validate BPM range
        let final_bpm = if bpm >= 50.0 && bpm <= 250.0 {
            tracing::info!("Spectrogram BPM analysis successful: {:.1} BPM", bpm);
            bpm
        } else {
            tracing::warn!("BPM analysis resulted in unrealistic value: {:.1}, using fallback (120 BPM)", bpm);
            120.0
        };

        Ok((final_bpm, spectrogram_path, visualization_path))
    }

    /// Download and analyze a remote audio file with spectrogram
    pub async fn analyze_remote_file_spectrogram(&self, url: &str) -> Result<(f32, String, String)> {
        tracing::info!("Starting remote spectrogram analysis for URL: {}", url);
        
        // Create a temporary file
        let temp_dir = std::env::temp_dir();
        let temp_file = temp_dir.join(format!("musestruct_spectrogram_{}.tmp", uuid::Uuid::new_v4()));
        let temp_path = temp_file.to_string_lossy().to_string();
        
        tracing::debug!("Created temporary file for spectrogram analysis: {}", temp_path);

        tracing::debug!("Downloading file from URL: {}", url);
        // Download the file
        let response = reqwest::get(url).await
            .map_err(|e| {
                let error_msg = format!("Failed to download file from URL '{}': {}", url, e);
                tracing::error!("{}", error_msg);
                anyhow!(error_msg)
            })?;
        
        let content_length = response.content_length();
        tracing::debug!("Download response received - Content length: {:?}", content_length);
        
        if !response.status().is_success() {
            let error_msg = format!("HTTP error when downloading file from '{}': {}", url, response.status());
            tracing::error!("{}", error_msg);
            return Err(anyhow!(error_msg));
        }
        
        let bytes = response.bytes().await
            .map_err(|e| {
                let error_msg = format!("Failed to read response bytes from URL '{}': {}", url, e);
                tracing::error!("{}", error_msg);
                anyhow!(error_msg)
            })?;
        tracing::info!("File downloaded successfully - Size: {} bytes", bytes.len());
        
        // Write to temporary file
        tokio::fs::write(&temp_file, bytes).await?;
        tracing::debug!("File written to temporary location: {}", temp_path);

        // Analyze the temporary file with spectrogram
        let result = self.analyze_bpm_with_spectrogram(&temp_path).await;

        // Clean up temporary file
        match tokio::fs::remove_file(&temp_file).await {
            Ok(_) => tracing::debug!("Temporary file cleaned up: {}", temp_path),
            Err(e) => tracing::warn!("Failed to clean up temporary file {}: {}", temp_path, e),
        }

        result
    }

    /// Generate full-song spectrogram
    fn generate_spectrogram(samples: &[f32], sample_rate: u32) -> Result<Spectrogram> {
        let mut spectrogram_data = Vec::new();
        let time_resolution = SPECTROGRAM_HOP_SIZE as f32 / sample_rate as f32;
        let freq_resolution = sample_rate as f32 / SPECTROGRAM_WINDOW_SIZE as f32;
        let duration = samples.len() as f32 / sample_rate as f32;
        
        // Process entire song in windows
        for window_start in (0..samples.len()).step_by(SPECTROGRAM_HOP_SIZE) {
            let window_end = (window_start + SPECTROGRAM_WINDOW_SIZE).min(samples.len());
            if window_end - window_start < SPECTROGRAM_WINDOW_SIZE / 2 {
                break; // Skip incomplete windows at the end
            }
            
            // Extract and pad window
            let mut window_samples = samples[window_start..window_end].to_vec();
            window_samples.resize(SPECTROGRAM_WINDOW_SIZE, 0.0);
            
            // Apply Hann window
            let windowed_samples = hann_window(&window_samples);
            
            // Calculate spectrum
            let spectrum_result = samples_fft_to_spectrum(
                &windowed_samples,
                sample_rate,
                FrequencyLimit::Range(LOW_FREQ_CUTOFF, HIGH_FREQ_CUTOFF),
                Some(&divide_by_N_sqrt),
            );
            
            match spectrum_result {
                Ok(spectrum) => {
                    // Extract magnitude data
                    let magnitudes: Vec<f32> = spectrum
                        .data()
                        .iter()
                        .map(|(_, magnitude)| magnitude.val())
                        .collect();
                    
                    spectrogram_data.push(magnitudes);
                }
                Err(e) => {
                    tracing::debug!("FFT failed for window starting at {}: {}", window_start, e);
                    continue;
                }
            }
        }
        
        if spectrogram_data.is_empty() {
            return Err(anyhow!("Failed to generate spectrogram data"));
        }
        
        Ok(Spectrogram {
            data: spectrogram_data,
            time_resolution,
            freq_resolution,
            min_freq: LOW_FREQ_CUTOFF,
            max_freq: HIGH_FREQ_CUTOFF,
            duration,
        })
    }

    /// Save spectrogram as an image file
    fn save_spectrogram_image(spectrogram: &Spectrogram, original_file_path: &str) -> Result<String> {
        let width = spectrogram.data.len();
        let height = spectrogram.data.first().map_or(0, |f| f.len());
        
        if width == 0 || height == 0 {
            return Err(anyhow!("Invalid spectrogram dimensions"));
        }
        
        // Create image buffer
        let mut img: RgbImage = ImageBuffer::new(width as u32, height as u32);
        
        // Find min/max values for normalization
        let mut min_val = f32::INFINITY;
        let mut max_val = f32::NEG_INFINITY;
        
        for frame in &spectrogram.data {
            for &magnitude in frame {
                min_val = min_val.min(magnitude);
                max_val = max_val.max(magnitude);
            }
        }
        
        let range = max_val - min_val;
        if range == 0.0 {
            return Err(anyhow!("No dynamic range in spectrogram"));
        }
        
        // Generate image with color mapping (blue to red via green)
        for (x, frame) in spectrogram.data.iter().enumerate() {
            for (y, &magnitude) in frame.iter().enumerate() {
                // Normalize to 0-1 range
                let normalized = (magnitude - min_val) / range;
                
                // Apply logarithmic scaling for better visualization
                let log_normalized = (normalized * 10.0 + 1.0).ln() / (11.0_f32.ln());
                let _intensity = (log_normalized * 255.0) as u8;
                
                // Color mapping: blue (low) -> green (mid) -> red (high)
                let (r, g, b) = if log_normalized < 0.5 {
                    let t = log_normalized * 2.0;
                    (0, (t * 255.0) as u8, (255.0 * (1.0 - t)) as u8)
                } else {
                    let t = (log_normalized - 0.5) * 2.0;
                    ((t * 255.0) as u8, (255.0 * (1.0 - t)) as u8, 0)
                };
                
                // Note: Image coordinates are flipped (y=0 is top)
                let img_y = (height - 1 - y) as u32;
                img.put_pixel(x as u32, img_y, Rgb([r, g, b]));
            }
        }
        
        // Generate output path
        let original_path = Path::new(original_file_path);
        let file_stem = original_path.file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown");
        
        let output_path = format!("./cache/spectrograms/spectrogram_{}.png", file_stem);
        
        // Create directory if it doesn't exist
        if let Some(parent) = Path::new(&output_path).parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        // Save image
        img.save(&output_path)
            .map_err(|e| anyhow!("Failed to save spectrogram image: {}", e))?;
        
        tracing::info!("Spectrogram image saved: {} ({}x{} pixels)", output_path, width, height);
        Ok(output_path)
    }

    /// Create analysis visualization showing spectrogram with overlaid beats and analysis data
    fn create_analysis_visualization(
        beats: &[SpectrogramBeat], 
        spectrogram: &Spectrogram, 
        analysis_cache: &AnalysisCache,
        original_file_path: &str, 
        detected_bpm: f32
    ) -> Result<String> {
        // Use actual spectrogram dimensions (same as normal spectrogram)
        let img_width = spectrogram.data.len() as u32;
        let img_height = spectrogram.data.first().map_or(0, |f| f.len()) as u32;
        
        if img_width == 0 || img_height == 0 {
            return Err(anyhow!("Invalid spectrogram dimensions for analysis visualization"));
        }
        
        // Create image buffer with black background
        let mut img: RgbImage = ImageBuffer::from_pixel(img_width, img_height, Rgb([0, 0, 0]));
        
        // Colors
        let yellow = Rgb([255, 255, 0]);
        
        // === SPECTROGRAM VISUALIZATION WITH OVERLAID BEATS (Full Image) ===
        // Find min/max values for normalization
        let mut min_val = f32::INFINITY;
        let mut max_val = f32::NEG_INFINITY;
        
        for frame in &spectrogram.data {
            for &magnitude in frame {
                min_val = min_val.min(magnitude);
                max_val = max_val.max(magnitude);
            }
        }
        
        let range = max_val - min_val;
        if range > 0.0 {
            // Draw spectrogram using direct pixel mapping (same as normal spectrogram)
            for (x, frame) in spectrogram.data.iter().enumerate() {
                for (y, &magnitude) in frame.iter().enumerate() {
                    // Normalize and apply logarithmic scaling
                    let normalized = (magnitude - min_val) / range;
                    let log_normalized = (normalized * 10.0 + 1.0).ln() / (11.0_f32.ln());
                    
                    // Color mapping: blue (low) -> green (mid) -> red (high)
                    let (r, g, b) = if log_normalized < 0.5 {
                        let t = log_normalized * 2.0;
                        (0, (t * 255.0) as u8, (255.0 * (1.0 - t)) as u8)
                    } else {
                        let t = (log_normalized - 0.5) * 2.0;
                        ((t * 255.0) as u8, (255.0 * (1.0 - t)) as u8, 0)
                    };
                    
                    // Note: Image coordinates are flipped (y=0 is top)
                    let img_y = img_height - 1 - y as u32;
                    img.put_pixel(x as u32, img_y, Rgb([r, g, b]));
                }
            }
            
            // Use cached analysis data instead of recalculating
            let frame_energies = &analysis_cache.frame_energies;
            let section_thresholds = &analysis_cache.section_thresholds;
            let energy_groups = &analysis_cache.energy_groups;
            let max_energy = analysis_cache.max_energy;
            
            // Draw visualizations
            if max_energy > 0.0 {
                // 1. Draw energy plot as white pixels
                for (frame_idx, _, energy) in frame_energies {
                    let x = *frame_idx as u32;
                    if x < img_width {
                        let normalized_energy = energy / max_energy;
                        let y = ((1.0 - normalized_energy) * (img_height - 1) as f32) as u32;
                        
                        if y < img_height {
                            img.put_pixel(x, y, Rgb([255, 255, 255])); // White for energy
                            
                            // Adjacent pixels for visibility
                            if y > 0 {
                                img.put_pixel(x, y - 1, Rgb([200, 200, 200]));
                            }
                            if y + 1 < img_height {
                                img.put_pixel(x, y + 1, Rgb([200, 200, 200]));
                            }
                        }
                    }
                }
                
                // 2. Draw threshold lines as gray pixels
                for &(section_start, section_end, threshold) in section_thresholds {
                    let normalized_threshold = threshold / max_energy;
                    let threshold_y = ((1.0 - normalized_threshold) * (img_height - 1) as f32) as u32;
                    
                    if threshold_y < img_height {
                        for x in section_start as u32..section_end as u32 {
                            if x < img_width {
                                img.put_pixel(x, threshold_y, Rgb([128, 128, 128])); // Gray for threshold
                            }
                        }
                    }
                }
                
                // 3. Draw cluster boxes (black outline, no fill)
                for group in energy_groups {
                    if group.is_empty() {
                        continue;
                    }
                    
                    // Find cluster bounds
                    let cluster_start_frame = group.first().unwrap().0 as u32;
                    let cluster_end_frame = group.last().unwrap().0 as u32;
                    
                    // Find min/max energy in cluster for box height
                    let mut min_cluster_energy = f32::INFINITY;
                    let mut max_cluster_energy = 0.0f32;
                    for &(_, _, energy, _, _) in group {
                        min_cluster_energy = min_cluster_energy.min(energy);
                        max_cluster_energy = max_cluster_energy.max(energy);
                    }
                    
                    let min_y = ((1.0 - max_cluster_energy / max_energy) * (img_height - 1) as f32) as u32;
                    let max_y = ((1.0 - min_cluster_energy / max_energy) * (img_height - 1) as f32) as u32;
                    
                    // Draw black box outline
                    let box_color = Rgb([0, 0, 0]); // Black
                    
                    // Top and bottom lines
                    for x in cluster_start_frame..=cluster_end_frame.min(img_width - 1) {
                        if min_y < img_height {
                            img.put_pixel(x, min_y, box_color);
                        }
                        if max_y < img_height && max_y != min_y {
                            img.put_pixel(x, max_y, box_color);
                        }
                    }
                    
                    // Left and right lines
                    for y in min_y..=max_y.min(img_height - 1) {
                        if cluster_start_frame < img_width {
                            img.put_pixel(cluster_start_frame, y, box_color);
                        }
                        if cluster_end_frame < img_width && cluster_end_frame != cluster_start_frame {
                            img.put_pixel(cluster_end_frame, y, box_color);
                        }
                    }
                }
            }
            
            // Overlay detected beats as vertical lines
            if !beats.is_empty() {
                let duration = spectrogram.duration;
                
                for beat in beats {
                    let relative_time = beat.timestamp / duration;
                    let x = (relative_time * img_width as f32) as u32;
                    
                    // Draw bright vertical line for beat
                    for y in 0..img_height {
                        if x < img_width {
                            // Use yellow for high visibility
                            img.put_pixel(x, y, yellow);
                        }
                    }
                }
            }
        }
        
        // Generate output path
        let original_path = Path::new(original_file_path);
        let file_stem = original_path.file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown");
        
        let output_path = format!("./cache/spectrograms/analysis_{}_{}bpm.png", file_stem, detected_bpm as u32);
        
        // Create directory if it doesn't exist
        if let Some(parent) = Path::new(&output_path).parent() {
            std::fs::create_dir_all(parent)?;
        }
        
        // Save image
        img.save(&output_path)
            .map_err(|e| anyhow!("Failed to save analysis visualization: {}", e))?;
        
        tracing::info!("Analysis visualization saved: {} ({}x{} pixels, {} beats)", 
                       output_path, img_width, img_height, beats.len());
        Ok(output_path)
    }

    /// Detect beats from spectrogram using adaptive clustering approach
    fn detect_beats_from_spectrogram(spectrogram: &Spectrogram) -> Result<(Vec<SpectrogramBeat>, AnalysisCache)> {
        // Step 1: Calculate energy for all frames
        let mut frame_energies = Vec::new();
        let mut frame_energies_for_cache = Vec::new();
        let mut max_energy = 0.0f32;
        
        for (frame_idx, frame_data) in spectrogram.data.iter().enumerate() {
            let timestamp = frame_idx as f32 * spectrogram.time_resolution;
            let total_energy: f32 = frame_data.iter().sum();
            let avg_energy = total_energy / frame_data.len() as f32;
            max_energy = max_energy.max(avg_energy);
            
            // Find dominant frequency
            let dominant_freq_idx = frame_data
                .iter()
                .enumerate()
                .max_by(|a, b| a.1.partial_cmp(b.1).unwrap_or(std::cmp::Ordering::Equal))
                .map(|(idx, _)| idx)
                .unwrap_or(0);
            let dominant_freq = spectrogram.min_freq + (dominant_freq_idx as f32 * spectrogram.freq_resolution);
            
            frame_energies.push((frame_idx, timestamp, avg_energy, dominant_freq));
            frame_energies_for_cache.push((frame_idx, timestamp, avg_energy));
        }
        
        // Step 2: Apply adaptive thresholding with local sections
        let section_size = 100; // ~580ms sections at current resolution
        let mut candidate_frames = Vec::new();
        let mut section_thresholds = Vec::new();
        
        for section_start in (0..frame_energies.len()).step_by(section_size / 2) { // 50% overlap
            let section_end = (section_start + section_size).min(frame_energies.len());
            let section = &frame_energies[section_start..section_end];
            
            if section.is_empty() {
                continue;
            }
            
            // Calculate threshold as percentage of energy range: min + (max - min) * 80%
            let min_energy = section.iter().map(|(_, _, energy, _)| *energy).fold(f32::INFINITY, |a, b| a.min(b));
            let max_energy = section.iter().map(|(_, _, energy, _)| *energy).fold(0.0f32, |a, b| a.max(b));
            let energy_range = max_energy - min_energy;
            let adaptive_threshold = min_energy + (energy_range * ADAPTIVE_THRESHOLD_PERCENTAGE);
            
            // Store threshold info for visualization cache
            section_thresholds.push((section_start, section_end, adaptive_threshold));
            
            // Find frames above threshold in this section
            for &(frame_idx, timestamp, energy, dominant_freq) in section {
                if energy > adaptive_threshold {
                    candidate_frames.push((frame_idx, timestamp, energy, dominant_freq, adaptive_threshold));
                }
            }
        }
        
        tracing::debug!("Found {} candidate frames above adaptive thresholds", candidate_frames.len());
        
        // Step 3: Group high-energy frames that are close together temporally
        let mut energy_groups = Vec::new();
        let max_group_gap = 0.05; // Max 50ms gap between frames in same group
        
        candidate_frames.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap()); // Sort by timestamp
        
        let mut current_group = Vec::new();
        let mut last_timestamp = -1.0f32;
        
        for candidate in candidate_frames {
            let (frame_idx, timestamp, energy, dominant_freq, threshold) = candidate;
            
            if current_group.is_empty() || timestamp - last_timestamp <= max_group_gap {
                // Add to current group
                current_group.push((frame_idx, timestamp, energy, dominant_freq, threshold));
                last_timestamp = timestamp;
            } else {
                // Start new group
                if !current_group.is_empty() {
                    energy_groups.push(current_group.clone());
                }
                current_group.clear();
                current_group.push((frame_idx, timestamp, energy, dominant_freq, threshold));
                last_timestamp = timestamp;
            }
        }
        
        // Don't forget the last group
        if !current_group.is_empty() {
            energy_groups.push(current_group);
        }
        
        tracing::debug!("Grouped candidates into {} energy clusters", energy_groups.len());
        
        // Step 4: Extract one beat from the middle of each group
        let mut beats = Vec::new();
        let num_groups = energy_groups.len(); // Store length before moving
        
        for group in &energy_groups {
            if group.is_empty() {
                continue;
            }
            
            // Find the temporal middle of the group
            let group_start_time = group.first().unwrap().1;
            let group_end_time = group.last().unwrap().1;
            let group_middle_time = (group_start_time + group_end_time) / 2.0;
            
            // Find the frame closest to the middle time
            let mut best_frame = &group[0];
            let mut best_distance = (group[0].1 - group_middle_time).abs();
            
            for frame in group {
                let distance = (frame.1 - group_middle_time).abs();
                if distance < best_distance {
                    best_distance = distance;
                    best_frame = frame;
                }
            }
            
            let (_, timestamp, energy, dominant_freq, threshold) = *best_frame;
            let confidence = (energy / threshold).min(2.0); // Confidence based on how much above threshold
            
            beats.push(SpectrogramBeat {
                timestamp,
                energy,
                dominant_freq,
                confidence,
            });
        }
        
        // Step 5: Final debouncing to ensure minimum spacing
        let debounced_beats = Self::debounce_spectrogram_beats(beats, 0.1); // Min 100ms between beats
        
        // Create analysis cache
        let analysis_cache = AnalysisCache {
            frame_energies: frame_energies_for_cache,
            section_thresholds,
            energy_groups,
            max_energy,
        };
        
        tracing::info!("Adaptive clustering beat detection: {} groups -> {} final beats", 
                       num_groups, debounced_beats.len());
        Ok((debounced_beats, analysis_cache))
    }

    /// Remove beats that are too close together
    fn debounce_spectrogram_beats(beats: Vec<SpectrogramBeat>, min_interval: f32) -> Vec<SpectrogramBeat> {
        if beats.is_empty() {
            return beats;
        }
        
        let mut debounced = Vec::new();
        let mut last_timestamp = -1.0f32;
        
        for beat in beats {
            if beat.timestamp - last_timestamp >= min_interval {
                debounced.push(beat.clone());
                last_timestamp = beat.timestamp;
            }
        }
        
        debounced
    }

    /// Calculate BPM using histogram-based interval analysis
    fn calculate_bpm_histogram(beats: &[SpectrogramBeat]) -> Result<f32> {
        if beats.len() < 3 {
            return Err(anyhow!("Not enough beats for histogram BPM calculation"));
        }
        
        // Calculate all intervals between consecutive beats
        let intervals: Vec<f32> = beats
            .windows(2)
            .map(|pair| pair[1].timestamp - pair[0].timestamp)
            .collect();
        
        tracing::debug!("Calculated {} intervals from {} beats", intervals.len(), beats.len());
        
        // Filter realistic intervals (30-300 BPM range)
        let filtered_intervals: Vec<f32> = intervals
            .into_iter()
            .filter(|&interval| interval >= 0.2 && interval <= 2.0)
            .collect();
        
        if filtered_intervals.is_empty() {
            return Err(anyhow!("No valid intervals after filtering"));
        }
        
        tracing::debug!("Filtered to {} valid intervals", filtered_intervals.len());
        
        // Create histogram with fine-grained bins
        let bin_size = 0.01; // 10ms bins for high precision
        let tolerance_bins = 2; // ±20ms tolerance
        
        let min_interval = filtered_intervals.iter().fold(f32::INFINITY, |a, &b| a.min(b));
        let max_interval = filtered_intervals.iter().fold(f32::NEG_INFINITY, |a, &b| a.max(b));
        
        let num_bins = ((max_interval - min_interval) / bin_size).ceil() as usize + 1;
        let mut histogram = vec![0usize; num_bins];
        
        // Populate histogram
        for &interval in &filtered_intervals {
            let bin_index = ((interval - min_interval) / bin_size) as usize;
            if bin_index < num_bins {
                histogram[bin_index] += 1;
            }
        }
        
        // Find peaks with tolerance
        let mut peak_scores = Vec::new();
        
        for (bin_idx, &count) in histogram.iter().enumerate() {
            if count == 0 {
                continue;
            }
            
            // Calculate score including neighboring bins
            let start_bin = bin_idx.saturating_sub(tolerance_bins);
            let end_bin = (bin_idx + tolerance_bins + 1).min(num_bins);
            
            let total_score: usize = histogram[start_bin..end_bin].iter().sum();
            let center_interval = min_interval + (bin_idx as f32 * bin_size);
            
            peak_scores.push((total_score, center_interval));
        }
        
        // Sort by score to find most common interval
        peak_scores.sort_by(|a, b| b.0.cmp(&a.0));
        
        if let Some((best_score, _)) = peak_scores.first() {
            // Calculate score threshold for averaging candidates
            let score_threshold = (*best_score as f32 * (1.0 - SCORE_DEVIATION_PERCENTAGE)) as usize;
            
            // Find all candidates within the score threshold
            let candidates_within_threshold: Vec<(usize, f32)> = peak_scores
                .iter()
                .filter(|(score, _)| *score >= score_threshold)
                .cloned()
                .collect();
            
            tracing::debug!("Found {} candidates within {}% of max score (threshold: {})", 
                           candidates_within_threshold.len(), 
                           SCORE_DEVIATION_PERCENTAGE * 100.0, 
                           score_threshold);
            
            // Calculate averaged BPM
            let averaged_bpm = if USE_WEIGHTED_AVERAGING {
                // Weighted average by score
                let total_weighted_bpm: f32 = candidates_within_threshold
                    .iter()
                    .map(|(score, interval)| (*score as f32) * (60.0 / interval))
                    .sum();
                let total_weight: f32 = candidates_within_threshold
                    .iter()
                    .map(|(score, _)| *score as f32)
                    .sum();
                
                if total_weight > 0.0 {
                    total_weighted_bpm / total_weight
                } else {
                    60.0 / candidates_within_threshold[0].1
                }
            } else {
                // Unweighted average
                let total_bpm: f32 = candidates_within_threshold
                    .iter()
                    .map(|(_, interval)| 60.0 / interval)
                    .sum();
                total_bpm / candidates_within_threshold.len() as f32
            };
            
            tracing::debug!("Histogram analysis - {} averaging of {} candidates -> BPM: {:.1}", 
                           if USE_WEIGHTED_AVERAGING { "Weighted" } else { "Unweighted" },
                           candidates_within_threshold.len(), 
                           averaged_bpm);
            
            // Log top candidates
            for (i, (score, interval)) in peak_scores.iter().take(10).enumerate() {
                let included = *score >= score_threshold;
                tracing::debug!("Candidate {}: {:.3}s (score: {}) -> BPM: {:.1} {}", 
                               i + 1, interval, score, 60.0 / interval,
                               if included { "[INCLUDED]" } else { "" });
            }
            
            // Check for subdivision patterns
            if averaged_bpm > 160.0 {
                let half_bpm = averaged_bpm / 2.0;
                let third_bpm = averaged_bpm / 3.0;
                
                if half_bpm >= 80.0 && half_bpm <= 160.0 {
                    tracing::info!("Using half-time subdivision: {:.1} BPM", half_bpm);
                    return Ok(half_bpm);
                } else if third_bpm >= 80.0 && third_bpm <= 160.0 {
                    tracing::info!("Using third-time subdivision: {:.1} BPM", third_bpm);
                    return Ok(third_bpm);
                }
            }
            
            Ok(averaged_bpm)
        } else {
            Err(anyhow!("No peaks found in histogram analysis"))
        }
    }

    /// Read audio file (reused from main service with minor modifications)
    fn read_audio_file(file_path: &str) -> Result<AudioTrack> {
        // Remove file:// prefix if present
        let clean_path = if file_path.starts_with("file://") {
            &file_path[7..]
        } else {
            file_path
        };

        let path = Path::new(clean_path);
        let extension = path.extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or("unknown")
            .to_lowercase();

        tracing::debug!("Reading audio file for spectrogram: {} (format: {})", clean_path, extension);

        // Try symphonia first, fallback to hound for WAV
        match Self::read_with_symphonia(clean_path) {
            Ok(track) => {
                tracing::info!("Successfully read audio file with symphonia: {}", clean_path);
                Ok(track)
            },
            Err(symphonia_err) => {
                tracing::debug!("Symphonia failed: {}", symphonia_err);
                
                if extension == "wav" {
                    tracing::debug!("Falling back to hound for WAV file");
                    Self::read_wav_with_hound(clean_path)
                } else {
                    Err(anyhow!(
                        "Failed to read audio file '{}': {}",
                        clean_path, symphonia_err
                    ))
                }
            }
        }
    }

    /// Read with symphonia (simplified version)
    fn read_with_symphonia(file_path: &str) -> Result<AudioTrack> {
        let file = File::open(file_path)
            .map_err(|e| anyhow!("Failed to open file '{}': {}", file_path, e))?;
        
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        let mut hint = Hint::new();
        if let Some(extension) = Path::new(file_path).extension() {
            if let Some(ext_str) = extension.to_str() {
                hint.with_extension(ext_str);
            }
        }

        let meta_opts: MetadataOptions = Default::default();
        let fmt_opts: FormatOptions = Default::default();

        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &fmt_opts, &meta_opts)
            .map_err(|e| anyhow!("Failed to probe audio format: {}", e))?;

        let mut format = probed.format;

        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
            .ok_or_else(|| anyhow!("No supported audio tracks found"))?;

        let dec_opts: DecoderOptions = Default::default();
        let mut decoder = symphonia::default::get_codecs()
            .make(&track.codec_params, &dec_opts)
            .map_err(|e| anyhow!("Failed to create decoder: {}", e))?;

        let track_id = track.id;
        let sample_rate = track.codec_params.sample_rate
            .ok_or_else(|| anyhow!("Sample rate not found in track"))?;

        let mut samples = Vec::new();
        let mut channel_count = None;

        loop {
            let packet = match format.next_packet() {
                Ok(packet) => packet,
                Err(SymphoniaError::ResetRequired) => {
                    return Err(anyhow!("Track list changed during decoding"));
                }
                Err(SymphoniaError::IoError(err)) => {
                    if err.kind() == std::io::ErrorKind::UnexpectedEof {
                        break;
                    } else {
                        return Err(anyhow!("IO error during decoding: {}", err));
                    }
                }
                Err(err) => {
                    return Err(anyhow!("Decoding error: {}", err));
                }
            };

            while !format.metadata().is_latest() {
                format.metadata().pop();
            }

            if packet.track_id() != track_id {
                continue;
            }

            match decoder.decode(&packet) {
                Ok(decoded) => {
                    if channel_count.is_none() {
                        channel_count = Some(decoded.spec().channels.count());
                    }

                    match decoded {
                        AudioBufferRef::F32(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend_from_slice(plane);
                            }
                        }
                        AudioBufferRef::U8(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| (s as f32 - 128.0) / 128.0));
                            }
                        }
                        AudioBufferRef::U16(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| (s as f32 - 32768.0) / 32768.0));
                            }
                        }
                        AudioBufferRef::U24(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| (s.into_u32() as f32 - 8388608.0) / 8388608.0));
                            }
                        }
                        AudioBufferRef::U32(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| (s as f32 - 2147483648.0) / 2147483648.0));
                            }
                        }
                        AudioBufferRef::S8(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| s as f32 / 128.0));
                            }
                        }
                        AudioBufferRef::S16(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| s as f32 / 32768.0));
                            }
                        }
                        AudioBufferRef::S24(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| s.inner() as f32 / 8388608.0));
                            }
                        }
                        AudioBufferRef::S32(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| s as f32 / 2147483648.0));
                            }
                        }
                        AudioBufferRef::F64(buf) => {
                            for plane in buf.planes().planes() {
                                samples.extend(plane.iter().map(|&s| s as f32));
                            }
                        }
                    }
                }
                Err(SymphoniaError::IoError(_)) => continue,
                Err(SymphoniaError::DecodeError(_)) => continue,
                Err(err) => {
                    return Err(anyhow!("Decode error: {}", err));
                }
            }
        }

        if samples.is_empty() {
            return Err(anyhow!("No audio samples decoded"));
        }

        // Convert to mono
        let mono_samples = if let Some(channels) = channel_count {
            if channels == 1 {
                samples
            } else {
                samples
                    .chunks(channels)
                    .map(|chunk| chunk.iter().sum::<f32>() / chunk.len() as f32)
                    .collect()
            }
        } else {
            samples
        };

        Ok(AudioTrack {
            samples: mono_samples,
            sample_rate,
        })
    }

    /// Read WAV with hound (simplified version)
    fn read_wav_with_hound(file_path: &str) -> Result<AudioTrack> {
        let mut reader = hound::WavReader::open(file_path)
            .map_err(|e| anyhow!("Failed to open WAV file '{}': {}", file_path, e))?;
        
        let spec = reader.spec();
        
        let samples: Vec<f32> = match spec.sample_format {
            hound::SampleFormat::Int => {
                match spec.bits_per_sample {
                    16 => {
                        reader
                            .samples::<i16>()
                            .map(|s| s.map(|sample| sample as f32 / i16::MAX as f32))
                            .collect::<Result<Vec<f32>, HoundError>>()
                            .map_err(|e| anyhow!("Failed to read 16-bit samples: {}", e))?
                    }
                    24 => {
                        reader
                            .samples::<i32>()
                            .map(|s| s.map(|sample| sample as f32 / (1 << 23) as f32))
                            .collect::<Result<Vec<f32>, HoundError>>()
                            .map_err(|e| anyhow!("Failed to read 24-bit samples: {}", e))?
                    }
                    32 => {
                        reader
                            .samples::<i32>()
                            .map(|s| s.map(|sample| sample as f32 / i32::MAX as f32))
                            .collect::<Result<Vec<f32>, HoundError>>()
                            .map_err(|e| anyhow!("Failed to read 32-bit samples: {}", e))?
                    }
                    _ => return Err(anyhow!("Unsupported bit depth: {} bits", spec.bits_per_sample)),
                }
            }
            hound::SampleFormat::Float => {
                reader
                    .samples::<f32>()
                    .collect::<Result<Vec<f32>, HoundError>>()
                    .map_err(|e| anyhow!("Failed to read float samples: {}", e))?
            }
        };
        
        // Convert to mono
        let mono_samples = if spec.channels == 1 {
            samples
        } else {
            samples
                .chunks(spec.channels as usize)
                .map(|chunk| chunk.iter().sum::<f32>() / chunk.len() as f32)
                .collect()
        };
        
        Ok(AudioTrack {
            samples: mono_samples,
            sample_rate: spec.sample_rate,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_spectrogram_bpm_service_creation() {
        let service = SpectrogramBpmAnalysisService::new();
        // Test service creation
        assert!(true);
    }
}
