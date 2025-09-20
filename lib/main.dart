import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/music_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/streaming_provider.dart';
import 'providers/saved_tracks_provider.dart';
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
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MusicProvider()),
        ChangeNotifierProvider(create: (_) => StreamingProvider()),
        ChangeNotifierProvider(create: (_) => SavedTracksProvider()),
      ],
      child: MaterialApp(
        title: 'Musestruct',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1), // Indigo
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
          ),
        ),
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
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
