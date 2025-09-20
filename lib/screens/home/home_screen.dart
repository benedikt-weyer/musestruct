import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/streaming_provider.dart';
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Load service status when the screen is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StreamingProvider>().loadServiceStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<StreamingProvider>().loadServiceStatus();
            },
          ),
        ],
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
            // Streaming services section
            const Text(
              'Streaming Services',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Consumer<StreamingProvider>(
              builder: (context, streamingProvider, child) {
                if (streamingProvider.isLoading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (streamingProvider.error != null) {
                  return Card(
                    color: Colors.red.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.error, color: Colors.red),
                      title: const Text('Error loading services'),
                      subtitle: Text(streamingProvider.error!),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          streamingProvider.loadServiceStatus();
                        },
                      ),
                    ),
                  );
                }

                return Column(
                  children: streamingProvider.services.map((service) {
                    return _buildServiceCard(context, service);
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
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

  Widget _buildServiceCard(BuildContext context, ConnectedServiceInfo service) {
    final isConnected = service.isConnected;
    final icon = isConnected ? Icons.check_circle : Icons.cancel;
    final iconColor = isConnected ? Colors.green : Colors.grey;
    final statusText = isConnected ? 'Connected' : 'Not Connected';
    final statusColor = isConnected ? Colors.green : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(service.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isConnected) ...[
              const SizedBox(height: 2),
              if (service.accountUsername != null) ...[
                Text(
                  'Account: ${service.accountUsername}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              if (service.connectedAt != null) ...[
                Text(
                  'Connected: ${_formatDate(service.connectedAt!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ],
        ),
        trailing: isConnected
            ? TextButton(
                onPressed: () => _showDisconnectDialog(context, service),
                child: const Text(
                  'Disconnect',
                  style: TextStyle(color: Colors.red),
                ),
              )
            : TextButton(
                onPressed: () => _showConnectDialog(context, service.name),
                child: const Text('Connect'),
              ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showConnectDialog(BuildContext context, String serviceName) {
    if (serviceName == 'qobuz') {
      _showQobuzConnectionDialog(context);
    } else if (serviceName == 'spotify') {
      _showSpotifyConnectionDialog(context);
    }
  }

  void _showDisconnectDialog(BuildContext context, ConnectedServiceInfo service) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Disconnect ${service.displayName}'),
        content: Text(
          'Are you sure you want to disconnect from ${service.displayName}? '
          'You will need to reconnect to use this service again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Disconnecting from ${service.displayName}...'),
                  duration: const Duration(seconds: 30),
                ),
              );

              final success = await context.read<StreamingProvider>()
                  .disconnectService(service.name);

              scaffoldMessenger.hideCurrentSnackBar();

              if (success) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Successfully disconnected from ${service.displayName}'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                final error = context.read<StreamingProvider>().error;
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(error ?? 'Failed to disconnect'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
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
                  // Refresh service status
                  context.read<StreamingProvider>().loadServiceStatus();
                  
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
              // Refresh service status even for placeholder
              context.read<StreamingProvider>().loadServiceStatus();
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
