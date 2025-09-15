import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/music_provider.dart';
import '../../widgets/backend_status_indicator.dart';
import '../music/search_screen.dart';
import '../../widgets/music_player_bar.dart';
import '../../services/api_service.dart';
import '../../widgets/copyable_error.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const SearchScreen(),
    const Center(child: Text('Library\n(Coming Soon)', textAlign: TextAlign.center)),
    const Center(child: Text('Playlists\n(Coming Soon)', textAlign: TextAlign.center)),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(child: _screens[_selectedIndex]),
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
          // Floating status indicator
          const Positioned(
            top: 16,
            right: 16,
            child: BackendStatusIndicator(compact: true),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Library',
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
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                final user = authProvider.user;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(user?.username.substring(0, 1).toUpperCase() ?? 'U'),
                    ),
                    title: Text(user?.username ?? 'Unknown'),
                    subtitle: Text(user?.email ?? 'No email'),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Backend status card
            const BackendStatusCard(),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('Connect Qobuz'),
              subtitle: const Text('Connect your Qobuz account for hi-fi streaming'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                _showQobuzConnectionDialog(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('Connect Spotify'),
              subtitle: const Text('Connect your Spotify account for music streaming'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                _showSpotifyConnectionDialog(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () {
                _showLogoutDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQobuzConnectionDialog(BuildContext context) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect Qobuz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: 'Qobuz Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Qobuz Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = usernameController.text.trim();
              final password = passwordController.text.trim();
              
              if (username.isEmpty || password.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Please enter both username and password'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              
              Navigator.of(dialogContext).pop();
              
              // Show loading indicator
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Connecting to Qobuz...'),
                  duration: Duration(seconds: 30),
                ),
              );
              
              try {
                final response = await ApiService.connectQobuz(username, password);
                
                scaffoldMessenger.hideCurrentSnackBar();
                
                if (response.success) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Successfully connected to Qobuz!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  // Show copyable error - use the original context
                  if (context.mounted) {
                    CopyableErrorDialog.show(
                      context, 
                      response.message ?? 'Failed to connect to Qobuz',
                      title: 'Qobuz Connection Failed'
                    );
                  }
                }
              } catch (e) {
                scaffoldMessenger.hideCurrentSnackBar();
                if (context.mounted) {
                  CopyableErrorDialog.show(
                    context, 
                    'Network error: $e',
                    title: 'Connection Error'
                  );
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showSpotifyConnectionDialog(BuildContext context) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect Spotify'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Spotify integration requires OAuth2 authentication.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'To connect your Spotify account:',
            ),
            const SizedBox(height: 8),
            const Text('1. Visit the Spotify Developer Console'),
            const Text('2. Authorize the application'),
            const Text('3. Copy the access token'),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Access Token',
                border: OutlineInputBorder(),
                hintText: 'Paste your Spotify access token here',
              ),
              maxLines: 3,
              onChanged: (value) {
                // Store the token temporarily
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Spotify OAuth2 implementation coming soon!'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
