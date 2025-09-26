import 'package:flutter/material.dart';
import '../../playlists/models/playlist.dart';

class NavigationProvider extends ChangeNotifier {
  int _currentIndex = 0;
  BuildContext? _context;
  
  int get currentIndex => _currentIndex;
  
  void setContext(BuildContext context) {
    _context = context;
  }
  
  void setCurrentIndex(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      notifyListeners();
      // Don't use navigation for tab changes - just update the index
      // The UI will rebuild based on the current index
    }
  }
  
  void navigateToPlaylistDetail(String playlistId, Playlist playlist) {
    if (_context != null) {
      Navigator.of(_context!).pushNamed(
        '/playlist/$playlistId',
        arguments: playlist,
      );
    }
  }
  
  void updateIndexForRoute(String route) {
    int newIndex;
    switch (route) {
      case '/search':
        newIndex = 0;
        break;
      case '/my-tracks':
        newIndex = 1;
        break;
      case '/playlists':
        newIndex = 2;
        break;
      case '/settings':
        newIndex = 3;
        break;
      default:
        // For sub-routes like playlist detail, keep the current parent tab
        if (route.startsWith('/playlist/')) {
          newIndex = 2; // Keep playlists tab selected
        } else {
          return;
        }
    }
    
    if (_currentIndex != newIndex) {
      _currentIndex = newIndex;
      notifyListeners();
    }
  }
}
