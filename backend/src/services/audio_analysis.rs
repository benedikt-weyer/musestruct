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

// Analysis configuration
const WINDOW_SIZE: usize = 2048; // Power of 2 for efficient FFT
const HOP_SIZE: usize = WINDOW_SIZE / 4; // 75% overlap for better temporal resolution
const SAMPLE_RATE: u32 = 44100; // Standard sample rate
const LOW_FREQ_CUTOFF: f32 = 200.0; // Hz - focus on bass frequencies for beat detection
const BEAT_THRESHOLD: f32 = 0.25; // Energy threshold for beat detection (increased for more selectivity)

/// Represents a detected beat with timestamp
#[derive(Debug, Clone)]
struct Beat {
    timestamp: f32, // Time in seconds
    energy: f32,    // Beat energy/confidence
}

/// Audio analysis configuration
#[derive(Debug, Clone)]
struct AnalysisConfig {
    window_size: usize,
    hop_size: usize,
    sample_rate: u32,
    low_freq_cutoff: f32,
    beat_threshold: f32,
}

struct AudioTrack {
    pub samples: Vec<f32>,
    pub sample_rate: u32,
}

pub struct AudioAnalysisService;

impl AudioAnalysisService {
    pub fn new() -> Self {
        Self
    }

    /// Analyze BPM of an audio file
    pub async fn analyze_bpm(&self, file_path: &str) -> Result<f32> {
        tracing::info!("Starting BPM analysis for file: {}", file_path);
        let start_time = std::time::Instant::now();
        let file_path_owned = file_path.to_string();
        let file_path_for_logging = file_path_owned.clone();
        
        // Run the BPM analysis in a blocking task to avoid blocking the async runtime
        let bpm = task::spawn_blocking(move || {
            Self::analyze_bpm_blocking(&file_path_owned)
        }).await??;

        let analysis_duration = start_time.elapsed();
        tracing::info!("BPM analysis completed for file: {} - Result: {} BPM - Duration: {:?}", 
                       file_path_for_logging, bpm, analysis_duration);

        Ok(bpm)
    }

    /// Blocking BPM analysis using improved windowed approach
    fn analyze_bpm_blocking(file_path: &str) -> Result<f32> {
        tracing::debug!("Checking if file exists: {}", file_path);
        
        // Check if file exists
        if !Path::new(file_path).exists() {
            tracing::error!("Audio file not found: {}", file_path);
            return Err(anyhow!("Audio file not found: {}", file_path));
        }

        tracing::debug!("Reading audio file: {}", file_path);
        // Step 1: Read and prepare audio data
        let track = Self::read_audio_file(file_path)?;
        tracing::info!("Audio file loaded - Sample rate: {} Hz, Samples: {}, Duration: {:.2}s", 
                       track.sample_rate, track.samples.len(), 
                       track.samples.len() as f32 / track.sample_rate as f32);
        
        // Create analysis configuration
        let config = AnalysisConfig {
            window_size: WINDOW_SIZE,
            hop_size: HOP_SIZE,
            sample_rate: track.sample_rate,
            low_freq_cutoff: LOW_FREQ_CUTOFF,
            beat_threshold: BEAT_THRESHOLD,
        };
        
        tracing::debug!("Starting windowed beat detection...");
        // Step 2: Detect beats using windowed analysis
        let beats = Self::detect_beats_windowed(&track.samples, &config)?;
        tracing::info!("Beat detection completed - Found {} beats", beats.len());
        
        if beats.len() < 2 {
            tracing::warn!("Not enough beats detected for BPM calculation, using default");
            return Ok(120.0);
        }
        
        tracing::debug!("Calculating BPM from detected beats...");
        // Step 3: Calculate BPM from beat timestamps
        let bpm = Self::calculate_bpm_from_beats(&beats)?;
        tracing::debug!("Raw BPM calculation result: {:.1}", bpm);
        
        // Validate BPM range
        if bpm >= 50.0 && bpm <= 250.0 {
            tracing::info!("BPM analysis successful: {:.1} BPM", bpm);
            Ok(bpm)
        } else {
            tracing::warn!("BPM analysis resulted in unrealistic value: {:.1}, using fallback (120 BPM)", bpm);
            Ok(120.0)
        }
    }

    /// Reads an audio file and returns a vector of f32 samples.
    /// Supports multiple formats: WAV, MP3, FLAC, OGG, etc.
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

        tracing::debug!("Reading audio file: {} (format: {})", clean_path, extension);

        // Try to use symphonia for all formats first, fallback to hound for WAV
        match Self::read_with_symphonia(clean_path) {
            Ok(track) => {
                tracing::info!("Successfully read audio file with symphonia: {} ({})", clean_path, extension);
                Ok(track)
            },
            Err(symphonia_err) => {
                tracing::debug!("Symphonia failed for {}: {}", clean_path, symphonia_err);
                
                // Fallback to hound for WAV files
                if extension == "wav" {
                    tracing::debug!("Falling back to hound for WAV file: {}", clean_path);
                    Self::read_wav_with_hound(clean_path)
                } else {
                    Err(anyhow!(
                        "Failed to read audio file '{}' (format: {}): {}. Supported formats: WAV, MP3, FLAC, OGG, AAC, M4A",
                        clean_path, extension, symphonia_err
                    ))
                }
            }
        }
    }

    /// Read audio file using symphonia (supports multiple formats)
    fn read_with_symphonia(file_path: &str) -> Result<AudioTrack> {
        // Open the media source
        let file = File::open(file_path)
            .map_err(|e| anyhow!("Failed to open file '{}': {}", file_path, e))?;
        
        let mss = MediaSourceStream::new(Box::new(file), Default::default());

        // Create a probe hint using the file extension
        let mut hint = Hint::new();
        if let Some(extension) = Path::new(file_path).extension() {
            if let Some(ext_str) = extension.to_str() {
                hint.with_extension(ext_str);
            }
        }

        // Use the default options for metadata and format readers
        let meta_opts: MetadataOptions = Default::default();
        let fmt_opts: FormatOptions = Default::default();

        // Probe the media source
        let probed = symphonia::default::get_probe()
            .format(&hint, mss, &fmt_opts, &meta_opts)
            .map_err(|e| anyhow!("Failed to probe audio format: {}", e))?;

        // Get the instantiated format reader
        let mut format = probed.format;

        // Find the first audio track with a known (decodable) codec
        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
            .ok_or_else(|| anyhow!("No supported audio tracks found"))?;

        // Use the default options for the decoder
        let dec_opts: DecoderOptions = Default::default();

        // Create a decoder for the track
        let mut decoder = symphonia::default::get_codecs()
            .make(&track.codec_params, &dec_opts)
            .map_err(|e| anyhow!("Failed to create decoder: {}", e))?;

        // Store the track identifier, we'll use it to filter packets
        let track_id = track.id;
        let sample_rate = track.codec_params.sample_rate
            .ok_or_else(|| anyhow!("Sample rate not found in track"))?;

        let mut samples = Vec::new();
        let mut channel_count = None;

        // The decode loop
        loop {
            // Get the next packet from the media format
            let packet = match format.next_packet() {
                Ok(packet) => packet,
                Err(SymphoniaError::ResetRequired) => {
                    // The track list has been changed. Re-examine it and create a new set of decoders,
                    // then restart the decode loop. This is an advanced feature and we'll just error out.
                    return Err(anyhow!("Track list changed during decoding"));
                }
                Err(SymphoniaError::IoError(err)) => {
                    // The underlying media source encountered an error
                    if err.kind() == std::io::ErrorKind::UnexpectedEof {
                        // End of stream
                        break;
                    } else {
                        return Err(anyhow!("IO error during decoding: {}", err));
                    }
                }
                Err(err) => {
                    // A unrecoverable error occurred, halt decoding
                    return Err(anyhow!("Decoding error: {}", err));
                }
            };

            // Consume any new metadata that has been read since the last packet
            while !format.metadata().is_latest() {
                format.metadata().pop();
            }

            // If the packet does not belong to the selected track, skip over it
            if packet.track_id() != track_id {
                continue;
            }

            // Decode the packet into audio samples
            match decoder.decode(&packet) {
                Ok(decoded) => {
                    // Get channel count from first decoded buffer
                    if channel_count.is_none() {
                        channel_count = Some(decoded.spec().channels.count());
                    }

                    // Convert the decoded audio buffer to f32 samples
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
                Err(SymphoniaError::IoError(_)) => {
                    // The packet failed to decode due to an IO error, skip the packet
                    continue;
                }
                Err(SymphoniaError::DecodeError(_)) => {
                    // The packet failed to decode due to invalid data, skip the packet
                    continue;
                }
                Err(err) => {
                    // An unrecoverable error occurred, halt decoding
                    return Err(anyhow!("Decode error: {}", err));
                }
            }
        }

        if samples.is_empty() {
            return Err(anyhow!("No audio samples decoded"));
        }

        // Convert multi-channel to mono by averaging channels
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
            // Assume mono if channel count is unknown
            samples
        };

        Ok(AudioTrack {
            samples: mono_samples,
            sample_rate,
        })
    }

    /// Fallback method to read WAV files using hound
    fn read_wav_with_hound(file_path: &str) -> Result<AudioTrack> {
        let mut reader = hound::WavReader::open(file_path)
            .map_err(|e| anyhow!("Failed to open WAV file '{}': {}", file_path, e))?;
        
        let spec = reader.spec();
        
        // Handle different sample formats
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
        
        // Convert stereo to mono by averaging channels
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

    /// Detects beats using windowed analysis with spectrum analyzer
    fn detect_beats_windowed(samples: &[f32], config: &AnalysisConfig) -> Result<Vec<Beat>> {
        let mut beats = Vec::new();
        let mut previous_energy = 0.0f32;
        let mut energy_history = Vec::new();
        
        // Process audio in overlapping windows
        for (window_idx, window_start) in (0..samples.len()).step_by(config.hop_size).enumerate() {
            let window_end = (window_start + config.window_size).min(samples.len());
            if window_end - window_start < config.window_size / 2 {
                break; // Skip incomplete windows at the end
            }
            
            // Extract window samples and pad to power of 2 if needed
            let mut window_samples = samples[window_start..window_end].to_vec();
            
            // Pad with zeros to reach window_size (power of 2)
            window_samples.resize(config.window_size, 0.0);
            
            // Apply Hann window for better frequency resolution
            let windowed_samples = hann_window(&window_samples);
            
            // Calculate spectrum using spectrum-analyzer
            let spectrum_result = samples_fft_to_spectrum(
                &windowed_samples,
                config.sample_rate,
                FrequencyLimit::Range(20.0, config.low_freq_cutoff),
                Some(&divide_by_N_sqrt),
            );
            
            let spectrum = match spectrum_result {
                Ok(spectrum) => spectrum,
                Err(e) => {
                    tracing::debug!("FFT failed for window {}: {}", window_idx, e);
                    continue;
                }
            };
            
            // Calculate energy in low frequency range (bass frequencies where beats occur)
            let low_freq_energy: f32 = spectrum
                .data()
                .iter()
                .map(|(freq, magnitude)| {
                    if freq.val() <= config.low_freq_cutoff {
                        magnitude.val() * magnitude.val() // Energy = magnitude^2
                    } else {
                        0.0
                    }
                })
                .sum();
            
            // Store energy for adaptive thresholding
            energy_history.push(low_freq_energy);
            
            // Keep only recent history for adaptive threshold
            if energy_history.len() > 20 {
                energy_history.remove(0);
            }
            
            // Calculate adaptive threshold based on recent energy history
            let avg_energy = energy_history.iter().sum::<f32>() / energy_history.len() as f32;
            let adaptive_threshold = avg_energy * (1.0 + config.beat_threshold);
            
            // Beat detection: current energy significantly higher than recent average
            // and higher than previous window (onset detection) with stronger requirements
            if low_freq_energy > adaptive_threshold && low_freq_energy > previous_energy * 1.3 {
                let timestamp = window_start as f32 / config.sample_rate as f32;
                beats.push(Beat {
                    timestamp,
                    energy: low_freq_energy,
                });
            }
            
            previous_energy = low_freq_energy;
        }
        
        // Post-process beats to remove too-close detections (debouncing)
        let raw_beats_count = beats.len();
        let debounced_beats = Self::debounce_beats(beats, 0.15); // Minimum 150ms between beats (max 400 BPM)
        
        tracing::info!("Beat detection: {} raw beats -> {} debounced beats", 
                      raw_beats_count, debounced_beats.len());
        
        Ok(debounced_beats)
    }
    
    /// Remove beats that are too close together (debouncing)
    fn debounce_beats(beats: Vec<Beat>, min_interval: f32) -> Vec<Beat> {
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
    
    /// Calculate BPM from detected beats using interval analysis
    fn calculate_bpm_from_beats(beats: &[Beat]) -> Result<f32> {
        if beats.len() < 2 {
            return Err(anyhow!("Not enough beats for BPM calculation"));
        }
        
        // Calculate intervals between consecutive beats
        let intervals: Vec<f32> = beats
            .windows(2)
            .map(|pair| pair[1].timestamp - pair[0].timestamp)
            .collect();
        
        tracing::debug!("Calculated {} intervals from {} beats", intervals.len(), beats.len());
        
        if intervals.is_empty() {
            return Err(anyhow!("No intervals calculated"));
        }
        
        // Filter out unrealistic intervals (too fast or too slow)
        let filtered_intervals: Vec<f32> = intervals
            .into_iter()
            .filter(|&interval| interval >= 0.2 && interval <= 2.0) // 30-300 BPM range
            .collect();
        
        if filtered_intervals.is_empty() {
            return Err(anyhow!("No valid intervals after filtering"));
        }
        
        tracing::debug!("Filtered to {} valid intervals", filtered_intervals.len());
        
        // Use median interval for robustness against outliers
        let mut sorted_intervals = filtered_intervals.clone();
        sorted_intervals.sort_by(|a, b| a.partial_cmp(b).unwrap());
        
        let median_interval = sorted_intervals[sorted_intervals.len() / 2];
        let bpm = 60.0 / median_interval;
        
        tracing::debug!("Median interval: {:.3}s -> BPM: {:.1}", median_interval, bpm);
        
        // Additional validation: check if we might be detecting sub-beats
        // This is common when the algorithm picks up on both beats and off-beats
        if bpm > 160.0 {
            // Try different subdivisions to find the most musical result
            let half_time_bpm = bpm / 2.0;
            let third_time_bpm = bpm / 3.0;
            
            tracing::debug!("High BPM detected ({:.1}), trying subdivisions - Half: {:.1}, Third: {:.1}", 
                           bpm, half_time_bpm, third_time_bpm);
            
            // Prefer subdivisions that fall in typical musical BPM ranges
            if half_time_bpm >= 80.0 && half_time_bpm <= 160.0 {
                tracing::info!("Using half-time subdivision: {:.1} BPM (from {:.1})", half_time_bpm, bpm);
                return Ok(half_time_bpm);
            } else if third_time_bpm >= 80.0 && third_time_bpm <= 160.0 {
                tracing::info!("Using third-time subdivision: {:.1} BPM (from {:.1})", third_time_bpm, bpm);
                return Ok(third_time_bpm);
            }
        }
        
        Ok(bpm)
    }


    /// Download and analyze a remote audio file
    pub async fn analyze_remote_file(&self, url: &str) -> Result<f32> {
        tracing::info!("Starting remote file analysis for URL: {}", url);
        
        // Create a temporary file
        let temp_dir = std::env::temp_dir();
        let temp_file = temp_dir.join(format!("musestruct_analysis_{}.tmp", uuid::Uuid::new_v4()));
        let temp_path = temp_file.to_string_lossy().to_string();
        
        tracing::debug!("Created temporary file: {}", temp_path);

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

        // Analyze the temporary file
        let result = self.analyze_bpm(&temp_path).await;

        // Clean up temporary file
        match tokio::fs::remove_file(&temp_file).await {
            Ok(_) => tracing::debug!("Temporary file cleaned up: {}", temp_path),
            Err(e) => tracing::warn!("Failed to clean up temporary file {}: {}", temp_path, e),
        }

        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_audio_analysis_service_creation() {
        let service = AudioAnalysisService::new();
        // Just test that we can create the service
        assert!(true);
    }
}
