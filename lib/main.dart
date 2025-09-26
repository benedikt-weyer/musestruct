import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth/providers/auth_provider.dart';
import 'music/providers/music_provider.dart';
import 'core/providers/connectivity_provider.dart';
import 'music/providers/streaming_provider.dart';
import 'music/providers/saved_tracks_provider.dart';
import 'queue/providers/queue_provider.dart';
import 'playlists/providers/playlist_provider.dart';
import 'core/providers/theme_provider.dart';
import 'themes/app_themes.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
// import 'widgets/hidden_spotify_webview.dart'; // Disabled - WebView playback not working reliably

void main() {
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
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MusicProvider()),
        ChangeNotifierProvider(create: (_) => StreamingProvider()),
        ChangeNotifierProvider(create: (_) => SavedTracksProvider()),
        ChangeNotifierProvider(create: (_) => QueueProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
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
            body: Center(
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
          );
        }

        if (authProvider.isAuthenticated) {
          // Set up queue provider reference in music provider and initialize queue
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final musicProvider = Provider.of<MusicProvider>(context, listen: false);
            final queueProvider = Provider.of<QueueProvider>(context, listen: false);
            musicProvider.setQueueProvider(queueProvider);
            await queueProvider.initialize();
          });
          
          return const Stack(
            children: [
              HomeScreen(),
              // Hidden WebView for Spotify playback - DISABLED
              // HiddenSpotifyWebView(),
            ],
          );
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
