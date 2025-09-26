import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/navigation_provider.dart';
import '../../music/providers/music_provider.dart';
import 'music_player_bar.dart';

class BaseLayout extends StatelessWidget {
  final Widget child;

  const BaseLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Set context in navigation provider and update index based on current route
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigationProvider = Provider.of<NavigationProvider>(context, listen: false);
      navigationProvider.setContext(context);
      
      // Update the current index based on the current route
      final currentRoute = ModalRoute.of(context)?.settings.name;
      if (currentRoute != null) {
        navigationProvider.updateIndexForRoute(currentRoute);
      }
    });
    
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(child: child),
              // Music player bar at the bottom
              Consumer<MusicProvider>(
                builder: (context, musicProvider, child) {
                  if (musicProvider.currentTrack != null) {
                    return const MusicPlayerBar();
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Consumer<NavigationProvider>(
        builder: (context, navigationProvider, child) {
          return BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: navigationProvider.currentIndex,
            onTap: (index) => navigationProvider.setCurrentIndex(index),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.search),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.favorite),
                label: 'My Tracks',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.playlist_play),
                label: 'Playlists',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}
