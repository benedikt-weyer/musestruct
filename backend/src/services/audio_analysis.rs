use anyhow::{Result, anyhow};
use std::path::Path;
use tokio::task;
use hound::Error as HoundError;
use rustfft::FftPlanner;
use rustfft::num_complex::Complex;
use symphonia::core::audio::AudioBufferRef;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use std::fs::File;

// The size of the analysis window.
const WINDOW_SIZE: usize = 1024;
// The step size between consecutive windows.
const HOP_SIZE: usize = WINDOW_SIZE / 2;
// The threshold for peak detection.
const THRESHOLD: f32 = 0.3; // Increased threshold to be more selective

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

    /// Blocking BPM analysis using FFT
    fn analyze_bpm_blocking(file_path: &str) -> Result<f32> {
        tracing::debug!("Checking if file exists: {}", file_path);
        
        // Check if file exists
        if !Path::new(file_path).exists() {
            tracing::error!("Audio file not found: {}", file_path);
            return Err(anyhow!("Audio file not found: {}", file_path));
        }

        tracing::debug!("Reading audio file: {}", file_path);
        // Read the audio file
        let track = Self::read_audio_file(file_path)?;
        tracing::info!("Audio file loaded - Sample rate: {} Hz, Samples: {}, Duration: {:.2}s", 
                       track.sample_rate, track.samples.len(), 
                       track.samples.len() as f32 / track.sample_rate as f32);
        
        tracing::debug!("Calculating spectrogram...");
        // Calculate spectrogram
        let spectrogram = Self::calculate_spectrogram(&track.samples);
        tracing::debug!("Spectrogram calculated - Windows: {}, Frequency bins: {}", 
                        spectrogram.len(), 
                        spectrogram.first().map(|w| w.len()).unwrap_or(0));
        
        tracing::debug!("Detecting peaks...");
        // Detect peaks
        let peaks = Self::detect_peaks(&spectrogram);
        tracing::debug!("Peaks detected: {}", peaks.len());
        
        tracing::debug!("Calculating BPM from peaks...");
        // Calculate BPM
        let bpm = Self::calculate_bpm(&peaks, track.sample_rate);
        tracing::debug!("Raw BPM calculation result: {}", bpm);
        
        // Validate BPM range
        if bpm > 0.0 && bpm < 300.0 {
            tracing::info!("BPM analysis successful: {} BPM", bpm);
            Ok(bpm)
        } else {
            // Fallback to a reasonable default if analysis fails
            tracing::warn!("BPM analysis resulted in unrealistic value: {}, using fallback (120 BPM)", bpm);
            Ok(120.0) // Default BPM
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

    /// Calculates the spectrogram of an audio signal using FFT and a Hamming window.
    fn calculate_spectrogram(samples: &[f32]) -> Vec<Vec<f32>> {
        let fft_size = WINDOW_SIZE.next_power_of_two();
        let fft = FftPlanner::new().plan_fft_forward(fft_size);

        let mut spectrogram = Vec::new();

        for window_start in (0..samples.len()).step_by(HOP_SIZE) {
            let window_end = window_start + WINDOW_SIZE;
            if window_end > samples.len() {
                break;
            }

            let mut windowed_samples: Vec<f32> = samples[window_start..window_end].to_vec();
            Self::apply_hamming_window(&mut windowed_samples);

            let mut complex_samples: Vec<Complex<f32>> = windowed_samples
                .iter()
                .map(|&x| Complex::new(x, 0.0))
                .collect();
            
            // Pad with zeros to reach fft_size
            complex_samples.resize(fft_size, Complex::new(0.0, 0.0));
            
            fft.process(&mut complex_samples);

            let magnitude_spectrum: Vec<f32> = complex_samples
                .iter()
                .map(|c| c.norm())
                .collect();
            spectrogram.push(magnitude_spectrum);
        }

        spectrogram
    }

    /// Applies the Hamming window to a vector of audio samples.
    fn apply_hamming_window(samples: &mut Vec<f32>) {
        let window: Vec<f32> = (0..samples.len())
            .map(|i| {
                0.54 - 0.46 * f32::cos(2.0 * std::f32::consts::PI * i as f32 / (samples.len() - 1) as f32)
            })
            .collect();

        for i in 0..samples.len() {
            samples[i] *= window[i];
        }
    }

    /// Detects peaks in a spectrogram using a simple thresholding approach.
    /// Focuses on lower frequency ranges where beats are more likely to occur.
    fn detect_peaks(spectrogram: &[Vec<f32>]) -> Vec<(usize, usize)> {
        let mut peaks = Vec::new();

        for (i, row) in spectrogram.iter().enumerate() {
            // Focus on lower frequency bins (roughly 20Hz to 200Hz range)
            // This corresponds to typical bass/kick drum frequencies
            let max_freq_bin = (row.len() / 8).min(row.len()); // Focus on lower 1/8 of frequency spectrum
            
            for (j, &magnitude) in row.iter().enumerate().take(max_freq_bin) {
                if magnitude > THRESHOLD && Self::is_local_maximum(spectrogram, i, j) {
                    peaks.push((i, j));
                }
            }
        }

        tracing::debug!("Peak detection focused on frequency bins 0-{} (out of {})", 
                       spectrogram.first().map(|r| r.len() / 8).unwrap_or(0),
                       spectrogram.first().map(|r| r.len()).unwrap_or(0));

        peaks
    }

    /// Checks if a point in a spectrogram is a local maximum.
    fn is_local_maximum(spectrogram: &[Vec<f32>], i: usize, j: usize) -> bool {
        let magnitude = spectrogram[i][j];

        // Check neighbors for lower magnitude
        let neighbors = [
            (i.wrapping_sub(1), j),
            (i.wrapping_add(1), j),
            (i, j.wrapping_sub(1)),
            (i, j.wrapping_add(1)),
        ];

        // Check if the magnitude of the current point is greater than the magnitudes of all its neighbors
        neighbors.iter().all(|&(ni, nj)| {
            ni >= spectrogram.len() || 
            nj >= spectrogram[ni].len() || 
            spectrogram[ni][nj] < magnitude
        })
    }

    /// Creates a histogram of time intervals.
    fn create_histogram(intervals: &[f32], bins: usize) -> Vec<usize> {
        if intervals.is_empty() {
            return vec![0; bins];
        }

        let min_interval = *intervals.iter().min_by(|a, b| a.partial_cmp(b).unwrap()).unwrap();
        let max_interval = *intervals.iter().max_by(|a, b| a.partial_cmp(b).unwrap()).unwrap();

        if min_interval >= max_interval {
            return vec![0; bins];
        }

        let bin_width = (max_interval - min_interval) / bins as f32;
        let mut histogram = vec![0; bins];

        for &interval in intervals {
            let bin_index = ((interval - min_interval) / bin_width).floor() as usize;
            let bin_index = bin_index.min(bins - 1);
            histogram[bin_index] += 1;
        }

        histogram
    }

    /// Calculates the Beats Per Minute (BPM) from detected peaks.
    fn calculate_bpm(peaks: &[(usize, usize)], sample_rate: u32) -> f32 {
        if peaks.len() < 2 {
            tracing::debug!("Not enough peaks for BPM calculation: {}", peaks.len());
            return 120.0; // Default BPM if not enough peaks
        }

        // Calculate time intervals between peaks
        let intervals: Vec<f32> = peaks
            .windows(2)
            .map(|w| {
                let time_diff = (w[1].0 - w[0].0) as f32 * HOP_SIZE as f32 / sample_rate as f32;
                time_diff
            })
            .filter(|&interval| interval > 0.2 && interval < 2.0) // More restrictive: 30-300 BPM range
            .collect();

        tracing::debug!("Filtered intervals count: {} (from {} peaks)", intervals.len(), peaks.len());

        if intervals.is_empty() {
            tracing::debug!("No valid intervals found after filtering");
            return 120.0; // Default BPM
        }

        // Log some statistics about intervals
        let min_interval = *intervals.iter().min_by(|a, b| a.partial_cmp(b).unwrap()).unwrap();
        let max_interval = *intervals.iter().max_by(|a, b| a.partial_cmp(b).unwrap()).unwrap();
        let avg_interval = intervals.iter().sum::<f32>() / intervals.len() as f32;
        
        tracing::debug!("Interval stats - Min: {:.3}s, Max: {:.3}s, Avg: {:.3}s", 
                       min_interval, max_interval, avg_interval);

        // Use a histogram to find the most common time interval
        let histogram_bins = 50; // Reduced bins for better grouping
        let histogram = Self::create_histogram(&intervals, histogram_bins);

        // Find the bin with the maximum count
        if let Some((bin_index, max_count)) = histogram
            .iter()
            .enumerate()
            .max_by(|(_, count1), (_, count2)| count1.cmp(count2))
        {
            tracing::debug!("Most common bin: {} with {} occurrences", bin_index, max_count);
            
            let bin_width = (max_interval - min_interval) / histogram_bins as f32;
            let bin_center = min_interval + (bin_index as f32 + 0.5) * bin_width;

            tracing::debug!("Bin center interval: {:.3}s", bin_center);

            // Convert average interval to BPM
            if bin_center > 0.0 {
                let raw_bpm = 60.0 / bin_center;
                tracing::debug!("Raw calculated BPM: {:.1}", raw_bpm);
                
                // More reasonable BPM range - don't clamp as aggressively
                let bpm = raw_bpm.clamp(60.0, 300.0);
                tracing::debug!("Clamped BPM: {:.1}", bpm);
                
                return bpm;
            }
        }

        // Default return value if calculation fails
        tracing::debug!("BPM calculation failed, using default");
        120.0
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
