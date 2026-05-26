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

// Additional imports for remote file support
use uuid;
use reqwest;

// Key analysis configuration
const KEY_WINDOW_SIZE: usize = 8192; // Larger window for better frequency resolution
const KEY_HOP_SIZE: usize = 1024; // Hop size for analysis
const SAMPLE_RATE: u32 = 44100;
const MIN_FREQ: f32 = 80.0; // A1 (55 Hz) to cover bass notes
const MAX_FREQ: f32 = 2000.0; // Up to about C7 for harmonic analysis

// Chromatic scale frequencies (A4 = 440 Hz)
const CHROMATIC_FREQUENCIES: [f32; 12] = [
    261.63, // C4
    277.18, // C#4/Db4
    293.66, // D4
    311.13, // D#4/Eb4
    329.63, // E4
    349.23, // F4
    369.99, // F#4/Gb4
    392.00, // G4
    415.30, // G#4/Ab4
    440.00, // A4
    466.16, // A#4/Bb4
    493.88, // B4
];

// Key names in standard notation
const KEY_NAMES: [&str; 24] = [
    "C", "G", "D", "A", "E", "B", "F#", "C#", "F", "Bb", "Eb", "Ab", // Major keys
    "Am", "Em", "Bm", "F#m", "C#m", "G#m", "D#m", "A#m", "Dm", "Gm", "Cm", "Fm", // Minor keys
];

// Camelot wheel notation (1A-12A for minor, 1B-12B for major)
const CAMELOT_NOTATION: [&str; 24] = [
    "8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "1B", "6B", "11B", "4B", // Major keys
    "5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A", // Minor keys
];

// Circle of fifths for major keys (starting from C)
const CIRCLE_OF_FIFTHS_MAJOR: [usize; 12] = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5];

// Circle of fifths for minor keys (starting from Am)
const CIRCLE_OF_FIFTHS_MINOR: [usize; 12] = [9, 4, 11, 6, 1, 8, 3, 10, 5, 0, 7, 2];

/// Represents a detected musical key
#[derive(Debug, Clone)]
pub struct MusicalKey {
    pub key_name: String,      // Standard notation (e.g., "C#", "Am")
    pub camelot: String,       // Camelot notation (e.g., "8A", "9B")
    pub confidence: f32,       // Confidence score (0.0 to 1.0)
    pub is_major: bool,        // True for major, false for minor
    pub key_index: usize,      // Index in the key arrays
}

/// Chromatic profile for key detection
#[derive(Debug)]
struct ChromaProfile {
    profile: [f32; 12], // Energy for each chromatic note
}

/// Audio track structure (reused from BPM analysis)
struct AudioTrack {
    pub samples: Vec<f32>,
    pub sample_rate: u32,
}

pub struct KeyAnalysisService;

impl KeyAnalysisService {
    pub fn new() -> Self {
        Self
    }

    /// Analyze the musical key of a track
    pub async fn analyze_key(&self, file_path: &str) -> Result<MusicalKey> {
        tracing::info!("Starting key analysis for file: {}", file_path);
        let start_time = std::time::Instant::now();
        let file_path_owned = file_path.to_string();
        let file_path_for_logging = file_path_owned.clone();
        
        // Run the analysis in a blocking task
        let key = task::spawn_blocking(move || {
            Self::analyze_key_blocking(&file_path_owned)
        }).await??;

        let analysis_duration = start_time.elapsed();
        tracing::info!("Key analysis completed for file: {} - Result: {} ({}) - Duration: {:?}", 
                       file_path_for_logging, key.key_name, key.camelot, analysis_duration);

        Ok(key)
    }

    /// Analyze key of a remote file
    pub async fn analyze_remote_file_key(&self, url: &str) -> Result<MusicalKey> {
        tracing::info!("Starting remote key analysis for URL: {}", url);
        
        // Create a temporary file
        let temp_dir = std::env::temp_dir();
        let temp_file = temp_dir.join(format!("musestruct_key_{}.tmp", uuid::Uuid::new_v4()));
        let temp_path = temp_file.to_string_lossy().to_string();
        
        tracing::debug!("Created temporary file for key analysis: {}", temp_path);

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
        let result = self.analyze_key(&temp_path).await;

        // Clean up temporary file
        match tokio::fs::remove_file(&temp_file).await {
            Ok(_) => tracing::debug!("Temporary file cleaned up: {}", temp_path),
            Err(e) => tracing::warn!("Failed to clean up temporary file {}: {}", temp_path, e),
        }

        result
    }

    /// Blocking key analysis
    fn analyze_key_blocking(file_path: &str) -> Result<MusicalKey> {
        tracing::debug!("Reading audio file for key analysis: {}", file_path);
        
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
        
        // Step 2: Generate chromatic profile
        tracing::debug!("Generating chromatic profile...");
        let chroma_profile = Self::generate_chroma_profile(&track.samples, track.sample_rate)?;
        tracing::debug!("Chromatic profile generated: {:?}", chroma_profile.profile);
        
        // Step 3: Detect key using template matching
        tracing::debug!("Detecting key using template matching...");
        let key = Self::detect_key_from_chroma(&chroma_profile)?;
        tracing::info!("Key detection completed: {} ({}), confidence: {:.3}", 
                       key.key_name, key.camelot, key.confidence);

        Ok(key)
    }

    /// Generate chromatic profile from audio samples
    fn generate_chroma_profile(samples: &[f32], sample_rate: u32) -> Result<ChromaProfile> {
        let mut chroma_bins = [0.0f32; 12];
        let mut total_energy = 0.0f32;
        let mut window_count = 0;

        // Process audio in overlapping windows
        for window_start in (0..samples.len()).step_by(KEY_HOP_SIZE) {
            let window_end = (window_start + KEY_WINDOW_SIZE).min(samples.len());
            if window_end - window_start < KEY_WINDOW_SIZE / 2 {
                break; // Skip incomplete windows at the end
            }
            
            // Extract and pad window
            let mut window_samples = samples[window_start..window_end].to_vec();
            window_samples.resize(KEY_WINDOW_SIZE, 0.0);
            
            // Apply Hann window
            let windowed_samples = hann_window(&window_samples);
            
            // Calculate spectrum
            let spectrum_result = samples_fft_to_spectrum(
                &windowed_samples,
                sample_rate,
                FrequencyLimit::Range(MIN_FREQ, MAX_FREQ),
                Some(&divide_by_N_sqrt),
            );
            
            match spectrum_result {
                Ok(spectrum) => {
                    // Map frequencies to chromatic bins
                    for (frequency, magnitude) in spectrum.data() {
                        let magnitude_val = magnitude.val();
                        total_energy += magnitude_val;
                        
                        // Convert frequency to chromatic bin
                        let chroma_bin = Self::frequency_to_chroma_bin(frequency.val());
                        chroma_bins[chroma_bin] += magnitude_val;
                    }
                    window_count += 1;
                }
                Err(e) => {
                    tracing::debug!("FFT failed for window starting at {}: {}", window_start, e);
                    continue;
                }
            }
        }
        
        if window_count == 0 {
            return Err(anyhow!("Failed to generate chromatic profile"));
        }

        // Normalize the chromatic profile
        if total_energy > 0.0 {
            for bin in &mut chroma_bins {
                *bin /= total_energy;
            }
        }

        Ok(ChromaProfile {
            profile: chroma_bins,
        })
    }

    /// Convert frequency to chromatic bin (0-11, where 0 = C)
    fn frequency_to_chroma_bin(frequency: f32) -> usize {
        // Convert frequency to MIDI note number
        let midi_note = 12.0 * (frequency / 440.0).log2() + 69.0; // A4 = 440Hz = MIDI 69
        
        // Get chromatic class (0-11)
        let chroma_class = (midi_note.round() as i32) % 12;
        
        // Ensure positive result
        ((chroma_class + 12) % 12) as usize
    }

    /// Detect key from chromatic profile using template matching
    fn detect_key_from_chroma(chroma_profile: &ChromaProfile) -> Result<MusicalKey> {
        let mut best_score = 0.0f32;
        let mut best_key_index = 0;
        let mut best_is_major = true;

        // Major key templates (Krumhansl-Schmuckler profiles)
        let major_template = [
            6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
        ];

        // Minor key templates
        let minor_template = [
            6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
        ];

        // Test all 12 major keys
        for root in 0..12 {
            let score = Self::calculate_template_correlation(&chroma_profile.profile, &major_template, root);
            if score > best_score {
                best_score = score;
                best_key_index = root;
                best_is_major = true;
            }
        }

        // Test all 12 minor keys
        for root in 0..12 {
            let score = Self::calculate_template_correlation(&chroma_profile.profile, &minor_template, root);
            if score > best_score {
                best_score = score;
                best_key_index = root;
                best_is_major = false;
            }
        }

        // Convert to key information
        let (key_name, camelot, final_key_index) = if best_is_major {
            let circle_index = CIRCLE_OF_FIFTHS_MAJOR.iter().position(|&x| x == best_key_index).unwrap_or(0);
            (KEY_NAMES[circle_index].to_string(), CAMELOT_NOTATION[circle_index].to_string(), circle_index)
        } else {
            let circle_index = CIRCLE_OF_FIFTHS_MINOR.iter().position(|&x| x == best_key_index).unwrap_or(0);
            let minor_index = circle_index + 12; // Minor keys start at index 12
            (KEY_NAMES[minor_index].to_string(), CAMELOT_NOTATION[minor_index].to_string(), minor_index)
        };

        // Normalize confidence score (0.0 to 1.0)
        let confidence = (best_score / 10.0).min(1.0).max(0.0);

        Ok(MusicalKey {
            key_name,
            camelot,
            confidence,
            is_major: best_is_major,
            key_index: final_key_index,
        })
    }

    /// Calculate correlation between chroma profile and key template
    fn calculate_template_correlation(chroma: &[f32; 12], template: &[f32; 12], root: usize) -> f32 {
        let mut correlation = 0.0f32;
        
        for i in 0..12 {
            let template_index = (i + root) % 12;
            correlation += chroma[i] * template[template_index];
        }
        
        correlation
    }

    /// Read audio file (reused from BPM analysis with minor modifications)
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

        tracing::debug!("Reading audio file for key analysis: {} (format: {})", clean_path, extension);

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
    async fn test_key_analysis_service_creation() {
        let service = KeyAnalysisService::new();
        // Test service creation
        assert!(true);
    }

    #[test]
    fn test_frequency_to_chroma_bin() {
        // Test A4 = 440Hz should map to chroma bin 9 (A)
        assert_eq!(KeyAnalysisService::frequency_to_chroma_bin(440.0), 9);
        
        // Test C4 = 261.63Hz should map to chroma bin 0 (C)
        assert_eq!(KeyAnalysisService::frequency_to_chroma_bin(261.63), 0);
        
        // Test C5 = 523.25Hz should also map to chroma bin 0 (C)
        assert_eq!(KeyAnalysisService::frequency_to_chroma_bin(523.25), 0);
    }
}
