import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:io' show Platform;
import 'auth/providers/auth_provider.dart';
import 'music/providers/music_provider.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/providers/navigation_provider.dart';
import 'music/providers/streaming_provider.dart';
import 'music/providers/saved_tracks_provider.dart';
import 'music/providers/saved_albums_provider.dart';
import 'queue/providers/queue_provider.dart';
import 'playlists/providers/playlist_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/api_service.dart';
import 'core/services/audio_service_handler.dart';
import 'core/themes/app_themes.dart';
import 'core/screens/auth/login_screen.dart';
import 'core/screens/home/home_screen.dart';
import 'core/screens/music/search_screen.dart';
import 'core/screens/music/my_tracks_screen.dart';
import 'core/screens/music/my_albums_screen.dart';
import 'core/screens/music/album_detail_screen.dart';
import 'core/screens/playlists/playlists_screen.dart';
import 'core/screens/playlists/playlist_detail_screen.dart';
import 'core/widgets/base_layout.dart';
import 'playlists/models/playlist.dart';
import 'music/models/music.dart';
// import 'core/widgets/hidden_spotify_webview.dart'; // Disabled - WebView playback not working reliably

// Global audio handler - initialized once at app startup
late MusestructAudioHandler _audioHandler;

Future<void> main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Log platform for debugging
  if (!kIsWeb) {
    debugPrint('Running on platform: ${Platform.operatingSystem}');
    if (Platform.isLinux) {
      debugPrint('MPRIS support will be automatically enabled via audio_service_mpris package');
    }
  }
  
  // Initialize audio service early for background audio support
  // This is critical for Android to keep audio playing when app is backgrounded
  try {
    _audioHandler = await AudioService.init(
      builder: () => MusestructAudioHandler(
        // Callbacks will be set later after providers are initialized
      ),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.musestruct.audio',
        androidNotificationChannelName: 'Musestruct Audio',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        // MPRIS-specific configuration for Linux
        artDownscaleWidth: 384,
        artDownscaleHeight: 384,
        fastForwardInterval: const Duration(seconds: 10),
        rewindInterval: const Duration(seconds: 10),
      ),
    );
    debugPrint('Audio service initialized successfully at app startup');
  } catch (e) {
    debugPrint('Failed to initialize audio service: $e');
    // Continue without audio service - the app will still work, just without media controls
  }
  
  runApp(const MusestructApp());
}

class MusestructApp extends StatelessWidget {
  const MusestructApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MusicProvider()),
        ChangeNotifierProvider(create: (_) => StreamingProvider()),
        ChangeNotifierProvider(create: (_) => SavedTracksProvider()),
        ChangeNotifierProvider(create: (_) => SavedAlbumsProvider()),
        ChangeNotifierProvider(create: (_) => QueueProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        Provider(create: (_) => ApiService()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Musestruct',
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AuthWrapper(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check authentication status on app start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).checkAuthStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground - resume normal UI updates
        musicProvider.resumeUIUpdates();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // App is in background - continue audio but pause UI updates
        musicProvider.pauseUIUpdates();
        break;
      case AppLifecycleState.hidden:
        // App is hidden - continue audio but pause UI updates
        musicProvider.pauseUIUpdates();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          return const Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note,
                      size: 64,
                      color: Color(0xFF6366F1),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Musestruct',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                    SizedBox(height: 32),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          );
        }

        if (authProvider.isAuthenticated) {
          // Set up queue provider reference in music provider and initialize queue
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final musicProvider = Provider.of<MusicProvider>(context, listen: false);
            final queueProvider = Provider.of<QueueProvider>(context, listen: false);
            final streamingProvider = Provider.of<StreamingProvider>(context, listen: false);
            
            musicProvider.setQueueProvider(queueProvider);
            await queueProvider.initialize();
            
            // Set up callbacks for the pre-initialized audio handler
            // This connects the audio service to the music provider after authentication
            try {
              _audioHandler.onPlayCallback = () async => await musicProvider.togglePlayPause();
              _audioHandler.onPauseCallback = () async => await musicProvider.togglePlayPause();
              _audioHandler.onStopCallback = () async => await musicProvider.stopPlayback();
              _audioHandler.onSeekCallback = (position) async => await musicProvider.seekTo(position);
              _audioHandler.onSkipToNextCallback = () async => await musicProvider.playNextTrack();
              _audioHandler.onSkipToPreviousCallback = () async => await musicProvider.playPreviousTrackFromPlaylist();
              
              musicProvider.setAudioServiceHandler(_audioHandler);
              debugPrint('Audio service callbacks connected to music provider');
            } catch (e) {
              debugPrint('Failed to connect audio service callbacks: $e');
            }
            
            // Load service status immediately after authentication
            streamingProvider.loadServiceStatus();
          });
          
          // Return the authenticated app with proper navigator
          return const AuthenticatedApp();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class AuthenticatedApp extends StatelessWidget {
  const AuthenticatedApp({super.key});

  final List<Widget> _screens = const [
    SearchScreen(),
    MyTracksScreen(),
    MyAlbumsScreen(),
    PlaylistsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) {
        Widget page;
        
        // Handle playlist detail route with parameters
        if (settings.name?.startsWith('/playlist/') == true) {
          final playlist = settings.arguments as Playlist?;
          if (playlist != null) {
            page = PlaylistDetailContent(playlist: playlist);
          } else {
            page = Consumer<NavigationProvider>(
              builder: (context, navigationProvider, child) {
                return _screens[navigationProvider.currentIndex];
              },
            );
          }
        }
        // Handle album detail route with parameters  
        else if (settings.name?.startsWith('/album/') == true) {
          final savedAlbum = settings.arguments as SavedAlbum?;
          if (savedAlbum != null) {
            page = AlbumDetailContent(savedAlbum: savedAlbum);
          } else {
            page = Consumer<NavigationProvider>(
              builder: (context, navigationProvider, child) {
                return _screens[navigationProvider.currentIndex];
              },
            );
          }
        } else {
          // For main tab navigation, show screen based on current index
          page = Consumer<NavigationProvider>(
            builder: (context, navigationProvider, child) {
              return _screens[navigationProvider.currentIndex];
            },
          );
        }
        
        return MaterialPageRoute(
          builder: (context) => BaseLayout(child: page),
          settings: settings,
        );
      },
    );
  }
}
