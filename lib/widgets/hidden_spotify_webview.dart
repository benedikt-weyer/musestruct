import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../music/providers/streaming_provider.dart';
import 'spotify_webview_widget.dart';

class HiddenSpotifyWebView extends StatefulWidget {
  const HiddenSpotifyWebView({super.key});

  @override
  State<HiddenSpotifyWebView> createState() => _HiddenSpotifyWebViewState();
}

class _HiddenSpotifyWebViewState extends State<HiddenSpotifyWebView> {
  String? _accessToken;

  @override
  void initState() {
    super.initState();
    // Use WidgetsBinding to defer the loading until after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAccessToken();
    });
  }

  Future<void> _loadAccessToken() async {
    try {
      // Get the access token from the streaming provider
      final streamingProvider = Provider.of<StreamingProvider>(context, listen: false);
      await streamingProvider.loadServiceStatus();
      
      // Find Spotify service and get access token
      final spotifyService = streamingProvider.services.firstWhere(
        (service) => service.name == 'spotify',
        orElse: () => throw Exception('Spotify not connected'),
      );
      
      // For now, we'll use a placeholder token
      // In a real implementation, you'd get this from the backend
      // and use spotifyService to get the actual token
      debugPrint('Found Spotify service: ${spotifyService.displayName}');
      
      if (mounted) {
        setState(() {
          _accessToken = 'placeholder_token';
        });
      }
    } catch (e) {
      debugPrint('Error loading Spotify access token: $e');
      // Don't set the token if there's an error
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accessToken != null) {
      return SpotifyWebViewWidget(
        accessToken: _accessToken!,
        onMessage: (message) {
          debugPrint('Spotify WebView message: $message');
        },
      );
    } else {
      return const SizedBox(
        width: 1,
        height: 1,
        child: Center(
          child: Text('Spotify WebView - Loading...'),
        ),
      );
    }
  }
}
