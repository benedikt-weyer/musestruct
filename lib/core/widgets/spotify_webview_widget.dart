import 'package:flutter/material.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';

// Global reference to the WebView widget for communication
class SpotifyWebViewManager {
  static _SpotifyWebViewWidgetState? _state;
  
  static void setState(_SpotifyWebViewWidgetState state) {
    _state = state;
  }
  
  static Future<void> playTrack(String trackUri) async {
    if (_state != null) {
      await _state!.playTrack(trackUri);
    } else {
      debugPrint('SpotifyWebViewWidget state not available');
    }
  }
}

class SpotifyWebViewWidget extends StatefulWidget {
  final String accessToken;
  final Function(String)? onMessage;
  final Function(String)? onPlayTrack;

  const SpotifyWebViewWidget({
    super.key,
    required this.accessToken,
    this.onMessage,
    this.onPlayTrack,
  });

  @override
  State<SpotifyWebViewWidget> createState() => _SpotifyWebViewWidgetState();
}

class _SpotifyWebViewWidgetState extends State<SpotifyWebViewWidget> {
  Webview? _webview;

  @override
  void initState() {
    super.initState();
    // Register this state globally
    SpotifyWebViewManager.setState(this);
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    try {
      debugPrint('Creating Spotify WebView window...');
      _webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowHeight: 600, // Larger window for debugging
          windowWidth: 800,  // Larger window for debugging
          title: "Spotify Web Playback SDK",
          titleBarTopPadding: 0,
          userDataFolderWindows: "spotify_webview",
        ),
      );

    if (_webview != null) {
      debugPrint('WebView window created successfully');
      _webview!.launch(_getSpotifyPlayerUrl());
      debugPrint('WebView launched with Spotify player URL');
      
      // Wait a bit for the page to load, then set the access token
      Future.delayed(const Duration(seconds: 5), () {
        _setAccessToken();
        _bringToFront();
      });
    } else {
      debugPrint('Failed to create WebView window');
    }
    } catch (e) {
      debugPrint('Error initializing WebView: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Return an empty widget since the WebView is a separate window
    return const SizedBox.shrink();
  }

  String _getSpotifyPlayerUrl() {
    // Use a simple data URL with inline HTML
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Web Playback SDK</title>
    <style>
        body {
            margin: 0;
            padding: 20px;
            background: #000;
            color: #fff;
            font-family: Arial, sans-serif;
        }
        #status {
            padding: 20px;
            text-align: center;
            font-size: 18px;
            border: 1px solid #333;
            border-radius: 8px;
            margin-bottom: 20px;
        }
        #debug {
            background: #111;
            padding: 10px;
            border-radius: 4px;
            font-family: monospace;
            font-size: 12px;
            max-height: 200px;
            overflow-y: auto;
        }
    </style>
</head>
<body>
    <div id="status">Loading Spotify Web Playback SDK...</div>
    <div id="debug"></div>

    <script>
        let player = null;
        let deviceId = null;
        let accessToken = 'PLACEHOLDER_TOKEN';

        function debugLog(message) {
            console.log(message);
            const debugDiv = document.getElementById('debug');
            debugDiv.innerHTML += new Date().toLocaleTimeString() + ': ' + message + '<br>';
            debugDiv.scrollTop = debugDiv.scrollHeight;
        }

        function updateStatus(message) {
            document.getElementById('status').textContent = message;
            debugLog('Status: ' + message);
        }

        // Initialize when SDK is ready
        window.onSpotifyWebPlaybackSDKReady = function() {
            debugLog('Spotify Web Playback SDK Ready');
            updateStatus('Spotify SDK Ready - Initializing player...');
            initializePlayer();
        };

           // Add a timeout to check if SDK loads
           setTimeout(function() {
               if (typeof window.Spotify === 'undefined') {
                   debugLog('Spotify Web Playback SDK failed to load');
                   updateStatus('Failed to load Spotify SDK');
               } else {
                   debugLog('Spotify SDK loaded successfully');
                   updateStatus('Spotify SDK loaded - waiting for ready event...');
               }
           }, 5000);

           // Add more frequent checks
           setInterval(function() {
               debugLog('SDK check - Spotify available: ' + (typeof window.Spotify !== 'undefined'));
               debugLog('SDK check - Player: ' + (player ? 'initialized' : 'null'));
               debugLog('SDK check - Device ID: ' + deviceId);
               debugLog('SDK check - Access token: ' + (accessToken ? 'present' : 'missing'));
               
               // If SDK is available but player is not initialized, try to initialize
               if (typeof window.Spotify !== 'undefined' && !player && accessToken && accessToken !== 'PLACEHOLDER_TOKEN') {
                   debugLog('Attempting manual initialization...');
                   initializePlayer();
               }
               
               // If player is initialized but no device ID, try to reconnect
               if (player && !deviceId) {
                   debugLog('Player exists but no device ID - attempting to reconnect...');
                   player.connect();
               }
           }, 2000);

        // Add more debugging
        debugLog('Script starting - access token: ' + (accessToken ? 'present' : 'missing'));
        updateStatus('Loading Spotify Web Playback SDK...');

        function initializePlayer() {
            debugLog('initializePlayer called');
            if (!accessToken || accessToken === 'PLACEHOLDER_TOKEN') {
                debugLog('No access token provided');
                updateStatus('No access token provided');
                return;
            }

            debugLog('Creating Spotify Player with token: ' + accessToken.substring(0, 10) + '...');
            updateStatus('Creating Spotify Player...');
            
            player = new Spotify.Player({
                name: 'Musestruct Player',
                getOAuthToken: function(cb) {
                    debugLog('getOAuthToken called, providing token');
                    cb(accessToken);
                },
                volume: 0.5
            });
            
            debugLog('Spotify Player created: ' + player);

               // Error handling
               player.addListener('initialization_error', function(data) {
                   debugLog('Initialization Error: ' + JSON.stringify(data));
                   updateStatus('Initialization Error: ' + data.message);
               });

               player.addListener('authentication_error', function(data) {
                   debugLog('Authentication Error: ' + JSON.stringify(data));
                   updateStatus('Authentication Error: ' + data.message);
               });

               player.addListener('account_error', function(data) {
                   debugLog('Account Error: ' + JSON.stringify(data));
                   updateStatus('Account Error: ' + data.message);
               });

               player.addListener('playback_error', function(data) {
                   debugLog('Playback Error: ' + JSON.stringify(data));
                   updateStatus('Playback Error: ' + data.message);
               });

               // Add more detailed error logging
               player.addListener('not_ready', function(data) {
                   debugLog('Not Ready: ' + JSON.stringify(data));
                   updateStatus('Not Ready: ' + JSON.stringify(data));
               });

            // Playback status updates
            player.addListener('player_state_changed', function(state) {
                debugLog('Player state changed: ' + JSON.stringify(state));
                handlePlayerStateChanged(state);
            });

               // Ready
               player.addListener('ready', function(data) {
                   debugLog('Ready with Device ID: ' + data.device_id);
                   deviceId = data.device_id;
                   updateStatus('Ready! Device ID: ' + data.device_id);
                   debugLog('Player is ready and connected');
                   
                   // Try to play the track immediately if we have one waiting
                   if (window.pendingTrackUri) {
                       debugLog('Playing pending track: ' + window.pendingTrackUri);
                       playTrack(window.pendingTrackUri);
                       window.pendingTrackUri = null;
                   }
               });

            // Not Ready
            player.addListener('not_ready', function(data) {
                debugLog('Device ID has gone offline: ' + data.device_id);
                updateStatus('Device offline: ' + data.device_id);
            });

               // Connect to the player
               debugLog('Connecting to Spotify Player...');
               updateStatus('Connecting to Spotify...');
               player.connect();
               
               // Add a timeout to force ready event if it doesn't fire
               setTimeout(function() {
                   if (!deviceId) {
                       debugLog('Timeout waiting for device ID - forcing ready event');
                       updateStatus('Timeout waiting for device ID');
                       
                       // Try to get device ID from player state
                       player.getCurrentState().then(function(state) {
                           debugLog('Current player state: ' + JSON.stringify(state));
                           if (state && state.device_id) {
                               deviceId = state.device_id;
                               debugLog('Got device ID from state: ' + deviceId);
                               updateStatus('Ready! Device ID: ' + deviceId);
                           }
                       });
                   }
               }, 10000); // 10 second timeout
        }

        function handlePlayerStateChanged(state) {
            if (!state) return;

            const isPlaying = !state.paused;
            const track = state.track_window && state.track_window.current_track;
            
            if (track) {
                const currentTrack = {
                    id: track.id,
                    title: track.name,
                    artist: track.artists && track.artists[0] ? track.artists[0].name : 'Unknown Artist',
                    album: track.album ? track.album.name : 'Unknown Album',
                    duration: Math.floor(track.duration_ms / 1000),
                    coverUrl: track.album && track.album.images && track.album.images[0] ? track.album.images[0].url : null,
                    source: 'spotify'
                };
                
                debugLog('Now playing: ' + JSON.stringify(currentTrack));
            }
        }

        // Function to play a specific track (called from Flutter)
        function playTrack(trackUri) {
            debugLog('=== playTrack function called ===');
            debugLog('Track URI: ' + trackUri);
            debugLog('Player state: ' + (player ? 'initialized' : 'null'));
            debugLog('Device ID: ' + deviceId);
            debugLog('Access token present: ' + (accessToken ? 'yes' : 'no'));

            updateStatus('playTrack called: ' + trackUri);

            if (player && deviceId) {
                debugLog('Player and device ready, attempting to play track...');
                updateStatus('Playing: ' + trackUri);

                // Use the Web Playback SDK to play the track
                const playUrl = 'https://api.spotify.com/v1/me/player/play?device_id=' + deviceId;
                debugLog('Making request to: ' + playUrl);

                fetch(playUrl, {
                    method: 'PUT',
                    body: JSON.stringify({
                        uris: [trackUri]
                    }),
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ' + accessToken
                    }
                }).then(function(response) {
                    debugLog('Response status: ' + response.status);

                    if (response.ok) {
                        debugLog('Track playback started via Web Playback SDK');
                        updateStatus('Playing: ' + trackUri);
                    } else {
                        debugLog('Failed to start playback: ' + response.status);
                        return response.text().then(function(text) {
                            debugLog('Response body: ' + text);
                            updateStatus('Failed to start playback: ' + response.status + ' - ' + text);
                        });
                    }
                }).catch(function(error) {
                    debugLog('Error starting playback: ' + error.message);
                    updateStatus('Error: ' + error.message);
                });
            } else {
                debugLog('Player not ready or no device ID - storing track for later');
                updateStatus('Player not ready - Player: ' + (player ? 'ready' : 'null') + ', Device: ' + (deviceId || 'null'));
                
                // Store the track URI to play when ready
                window.pendingTrackUri = trackUri;
                debugLog('Stored pending track: ' + trackUri);
            }
        }

        // Control functions
        function pauseTrack() {
            if (player) {
                player.pause();
            }
        }

        function resumeTrack() {
            if (player) {
                player.resume();
            }
        }

        function setVolume(volume) {
            if (player) {
                player.setVolume(volume);
            }
        }

        // Function to set access token
        function setAccessToken(token) {
            debugLog('Setting access token: ' + token.substring(0, 10) + '...');
            accessToken = token;
            
            // Test the token by making a simple API call
            fetch('https://api.spotify.com/v1/me', {
                headers: {
                    'Authorization': 'Bearer ' + token
                }
            }).then(function(response) {
                debugLog('Token test response status: ' + response.status);
                if (response.ok) {
                    debugLog('Token is valid');
                    return response.json();
                } else {
                    debugLog('Token validation failed: ' + response.status);
                    return response.text().then(function(text) {
                        debugLog('Token error response: ' + text);
                    });
                }
            }).then(function(data) {
                if (data) {
                    debugLog('User info: ' + JSON.stringify(data));
                }
            }).catch(function(error) {
                debugLog('Token test error: ' + error.message);
            });
            
            if (player) {
                debugLog('Player already exists, reinitializing...');
                initializePlayer();
            } else {
                debugLog('Player does not exist, initializing now...');
                initializePlayer();
            }
        }

        // Make functions globally available
        window.playTrack = playTrack;
        window.pauseTrack = pauseTrack;
        window.resumeTrack = resumeTrack;
        window.setVolume = setVolume;
        window.setAccessToken = setAccessToken;
        
        debugLog('Script loaded, waiting for Spotify SDK...');
    </script>
    
    <script src="https://sdk.scdn.co/spotify-player.js"></script>
</body>
</html>
    ''';
    
    return Uri.dataFromString(htmlContent, mimeType: 'text/html').toString();
  }

  String _getSpotifyPlayerHtml() {
    // Create a data URL with the Spotify Web Playback SDK HTML
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Web Playback SDK</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            background: #000;
            color: #fff;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        #status {
            padding: 20px;
            text-align: center;
        }
    </style>
</head>
<body>
    <div id="status">Initializing Spotify Web Playback SDK...</div>

    <script>
        let player = null;
        let deviceId = null;
        let accessToken = '${widget.accessToken}';

        // Initialize when SDK is ready
        window.onSpotifyWebPlaybackSDKReady = () => {
            console.log('Spotify Web Playback SDK Ready');
            updateStatus('Spotify SDK Ready - Initializing player...');
            initializePlayer();
        };

        // Add a timeout to check if SDK loads
        setTimeout(() => {
            if (typeof window.Spotify === 'undefined') {
                console.error('Spotify Web Playback SDK failed to load');
                updateStatus('Failed to load Spotify SDK');
            } else {
                console.log('Spotify SDK loaded successfully');
                updateStatus('Spotify SDK loaded - waiting for ready event...');
            }
        }, 5000);

        // Add more debugging
        console.log('Script starting - access token:', accessToken ? 'present' : 'missing');
        updateStatus('Loading Spotify Web Playback SDK...');

        function initializePlayer() {
            console.log('initializePlayer called');
            if (!accessToken) {
                console.error('No access token provided');
                updateStatus('No access token provided');
                return;
            }

            console.log('Creating Spotify Player with token:', accessToken.substring(0, 10) + '...');
            updateStatus('Creating Spotify Player...');
            
            player = new Spotify.Player({
                name: 'Musestruct Player',
                getOAuthToken: cb => {
                    console.log('getOAuthToken called, providing token');
                    cb(accessToken);
                },
                volume: 0.5
            });
            
            console.log('Spotify Player created:', player);

            // Error handling
            player.addListener('initialization_error', ({ message }) => {
                console.error('Initialization Error:', message);
                updateStatus('Initialization Error: ' + message);
            });

            player.addListener('authentication_error', ({ message }) => {
                console.error('Authentication Error:', message);
                updateStatus('Authentication Error: ' + message);
            });

            player.addListener('account_error', ({ message }) => {
                console.error('Account Error:', message);
                updateStatus('Account Error: ' + message);
            });

            player.addListener('playback_error', ({ message }) => {
                console.error('Playback Error:', message);
                updateStatus('Playback Error: ' + message);
            });

            // Playback status updates
            player.addListener('player_state_changed', state => {
                console.log('Player state changed:', state);
                handlePlayerStateChanged(state);
            });

            // Ready
            player.addListener('ready', ({ device_id }) => {
                console.log('Ready with Device ID', device_id);
                deviceId = device_id;
                updateStatus('Ready! Device ID: ' + device_id);
                console.log('Player is ready and connected');
            });

            // Not Ready
            player.addListener('not_ready', ({ device_id }) => {
                console.log('Device ID has gone offline', device_id);
                updateStatus('Device offline: ' + device_id);
            });

            // Connect to the player
            console.log('Connecting to Spotify Player...');
            updateStatus('Connecting to Spotify...');
            player.connect();
        }

        function handlePlayerStateChanged(state) {
            if (!state) return;

            const isPlaying = !state.paused;
            const track = state.track_window?.current_track;
            
            if (track) {
                const currentTrack = {
                    id: track.id,
                    title: track.name,
                    artist: track.artists?.[0]?.name || 'Unknown Artist',
                    album: track.album?.name || 'Unknown Album',
                    duration: Math.floor(track.duration_ms / 1000),
                    coverUrl: track.album?.images?.[0]?.url,
                    source: 'spotify'
                };
                
                console.log('Now playing:', currentTrack);
            }
        }

        function updateStatus(message) {
            document.getElementById('status').textContent = message;
        }

        // Function to play a specific track (called from Flutter)
        function playTrack(trackUri) {
            console.log('=== playTrack function called ===');
            console.log('Track URI:', trackUri);
            console.log('Player state:', player ? 'initialized' : 'null');
            console.log('Device ID:', deviceId);
            console.log('Access token present:', accessToken ? 'yes' : 'no');
            
            updateStatus('playTrack called: ' + trackUri);
            
            if (player && deviceId) {
                console.log('Player and device ready, attempting to play track...');
                updateStatus('Playing: ' + trackUri);
                
                // Use the Web Playback SDK to play the track
                const playUrl = 'https://api.spotify.com/v1/me/player/play?device_id=' + deviceId;
                console.log('Making request to:', playUrl);
                
                fetch(playUrl, {
                    method: 'PUT',
                    body: JSON.stringify({
                        uris: [trackUri]
                    }),
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ' + accessToken
                    }
                }).then(response => {
                    console.log('Response status:', response.status);
                    console.log('Response headers:', response.headers);
                    
                    if (response.ok) {
                        console.log('Track playback started via Web Playback SDK');
                        updateStatus('Playing: ' + trackUri);
                    } else {
                        console.error('Failed to start playback:', response.status);
                        return response.text().then(text => {
                            console.error('Response body:', text);
                            updateStatus('Failed to start playback: ' + response.status + ' - ' + text);
                        });
                    }
                }).catch(error => {
                    console.error('Error starting playback:', error);
                    updateStatus('Error: ' + error.message);
                });
            } else {
                console.error('Player not ready or no device ID');
                updateStatus('Player not ready - Player: ' + (player ? 'ready' : 'null') + ', Device: ' + (deviceId || 'null'));
            }
        }

        // Control functions
        function pauseTrack() {
            if (player) {
                player.pause();
            }
        }

        function resumeTrack() {
            if (player) {
                player.resume();
            }
        }

        function setVolume(volume) {
            if (player) {
                player.setVolume(volume);
            }
        }

        // Make functions globally available
        window.playTrack = playTrack;
        window.pauseTrack = pauseTrack;
        window.resumeTrack = resumeTrack;
        window.setVolume = setVolume;
    </script>
    
    <script src="https://sdk.scdn.co/spotify-player.js"></script>
</body>
</html>
    ''';

    return Uri.dataFromString(htmlContent, mimeType: 'text/html').toString();
  }

  Future<void> _setAccessToken() async {
    if (_webview != null) {
      try {
        debugPrint('Attempting to set access token in WebView...');
        await _webview!.evaluateJavaScript('setAccessToken("${widget.accessToken}");');
        debugPrint('Access token set in WebView successfully');
      } catch (e) {
        debugPrint('Error setting access token: $e');
        // Try again after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          _setAccessToken();
        });
      }
    }
  }

  Future<void> _bringToFront() async {
    if (_webview != null) {
      try {
        // Try to bring the window to the front
        await _webview!.evaluateJavaScript('window.focus();');
        debugPrint('WebView window brought to front');
      } catch (e) {
        debugPrint('Error bringing WebView to front: $e');
      }
    }
  }

  Future<void> _checkWebViewStatus() async {
    if (_webview != null) {
      try {
        final result = await _webview!.evaluateJavaScript('document.readyState;');
        debugPrint('WebView document ready state: $result');
        
        final title = await _webview!.evaluateJavaScript('document.title;');
        debugPrint('WebView document title: $title');
        
        final status = await _webview!.evaluateJavaScript('document.getElementById("status").textContent;');
        debugPrint('WebView status: $status');
      } catch (e) {
        debugPrint('Error checking WebView status: $e');
      }
    }
  }

  Future<void> playTrack(String trackUri) async {
    if (_webview != null) {
      debugPrint('Calling JavaScript playTrack with: $trackUri');
      
      // First check the WebView status
      await _checkWebViewStatus();
      
      // Check player status
      await checkPlayerStatus();
      
      // Try to force initialize if player is not ready
      await forceInitialize();
      
      // Wait a bit for initialization
      await Future.delayed(const Duration(seconds: 3));
      
      // Check player status again
      await checkPlayerStatus();
      
      // Try to force ready if no device ID
      await forceReady();
      
      // Wait a bit more
      await Future.delayed(const Duration(seconds: 2));
      
      // Check player status one more time
      await checkPlayerStatus();
      
      try {
        await _webview!.evaluateJavaScript('playTrack("$trackUri");');
        debugPrint('JavaScript playTrack call completed');
        
        // Check status again after calling playTrack
        Future.delayed(const Duration(seconds: 2), () {
          _checkWebViewStatus();
          checkPlayerStatus();
        });
      } catch (e) {
        debugPrint('Error calling JavaScript playTrack: $e');
      }
    } else {
      debugPrint('WebView is null, cannot play track');
    }
  }

  Future<void> pauseTrack() async {
    if (_webview != null) {
      await _webview!.evaluateJavaScript('pauseTrack();');
    }
  }

  Future<void> resumeTrack() async {
    if (_webview != null) {
      await _webview!.evaluateJavaScript('resumeTrack();');
    }
  }

  Future<void> setVolume(double volume) async {
    if (_webview != null) {
      await _webview!.evaluateJavaScript('setVolume($volume);');
    }
  }

  Future<void> forceInitialize() async {
    if (_webview != null) {
      debugPrint('Force initializing Spotify player...');
      try {
        await _webview!.evaluateJavaScript('initializePlayer();');
        debugPrint('Force initialization completed');
      } catch (e) {
        debugPrint('Error during force initialization: $e');
      }
    }
  }

  Future<void> checkPlayerStatus() async {
    if (_webview != null) {
      try {
        final deviceId = await _webview!.evaluateJavaScript('deviceId;');
        final playerReady = await _webview!.evaluateJavaScript('player ? "ready" : "null";');
        debugPrint('Player status - Device ID: $deviceId, Player: $playerReady');
      } catch (e) {
        debugPrint('Error checking player status: $e');
      }
    }
  }

  Future<void> forceReady() async {
    if (_webview != null) {
      debugPrint('Force triggering ready event...');
      try {
        await _webview!.evaluateJavaScript('''
          if (player) {
            player.getCurrentState().then(function(state) {
              debugLog('Force ready - Current state: ' + JSON.stringify(state));
              if (state && state.device_id) {
                deviceId = state.device_id;
                debugLog('Force ready - Got device ID: ' + deviceId);
                updateStatus('Ready! Device ID: ' + deviceId);
              } else {
                debugLog('Force ready - No device ID in state');
                updateStatus('No device ID available');
              }
            });
          }
        ''');
        debugPrint('Force ready completed');
      } catch (e) {
        debugPrint('Error during force ready: $e');
      }
    }
  }

  @override
  void dispose() {
    _webview?.close();
    super.dispose();
  }
}
