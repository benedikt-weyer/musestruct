import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/streaming_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/backend_status_indicator.dart';
import '../music/search_screen.dart';
import '../music/my_tracks_screen.dart';
import '../playlists/playlists_screen.dart';
import '../../widgets/music_player_bar.dart';
import '../../music/services/music_api_service.dart';
import '../../music/services/spotify_api_service.dart';
import '../../services/app_config_service.dart';
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
    const MyTracksScreen(),
    const PlaylistsScreen(),
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
          // Floating theme toggle button
          Positioned(
            top: 16,
            left: 16,
            child: Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return FloatingActionButton.small(
                  onPressed: () => themeProvider.toggleTheme(),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: Icon(themeProvider.themeModeIcon),
                );
              },
            ),
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
  final _backendUrlController = TextEditingController();
  bool _isBackendConfigExpanded = false;
  String? _backendSuccessMessage;
  String? _backendErrorMessage;

  @override
  void initState() {
    super.initState();
    // Load service status when the screen is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StreamingProvider>().loadServiceStatus();
      _loadBackendUrl();
    });
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadBackendUrl() async {
    try {
      final currentUrl = await AppConfigService.instance.getBackendUrl();
      _backendUrlController.text = currentUrl;
    } catch (e) {
      setState(() {
        _backendErrorMessage = 'Failed to load backend URL: $e';
      });
    }
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
            // Backend Configuration section
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.cloud),
                title: const Text('Backend Configuration'),
                subtitle: const Text('Configure server connection'),
                initiallyExpanded: _isBackendConfigExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _isBackendConfigExpanded = expanded;
                  });
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _backendUrlController,
                          decoration: InputDecoration(
                            labelText: 'Backend URL',
                            hintText: 'http://127.0.0.1:8080',
                            prefixIcon: const Icon(Icons.link),
                            border: const OutlineInputBorder(),
                            helperText: 'URL of the Musestruct backend server',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () {
                                _backendUrlController.text = AppConfigService.defaultBackendUrl;
                              },
                              tooltip: 'Reset to default',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Status Messages
                        if (_backendSuccessMessage != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_backendSuccessMessage!)),
                              ],
                            ),
                          ),
                        
                        if (_backendErrorMessage != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_backendErrorMessage!)),
                              ],
                            ),
                          ),
                        
                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _saveBackendUrl,
                                icon: const Icon(Icons.save),
                                label: const Text('Save'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _testConnection,
                                icon: const Icon(Icons.wifi_protected_setup),
                                label: const Text('Test'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Theme settings section
            const Text(
              'Appearance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return Card(
                  child: ListTile(
                    leading: Icon(themeProvider.themeModeIcon),
                    title: const Text('Theme'),
                    subtitle: Text(themeProvider.themeModeName),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _showThemeDialog(context, themeProvider),
                  ),
                );
              },
            ),
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

  Future<void> _saveBackendUrl() async {
    final url = _backendUrlController.text.trim();
    
    if (url.isEmpty) {
      setState(() {
        _backendErrorMessage = 'Please enter a backend URL';
        _backendSuccessMessage = null;
      });
      return;
    }

    if (!AppConfigService.isValidBackendUrl(url)) {
      setState(() {
        _backendErrorMessage = 'Please enter a valid URL (e.g., http://127.0.0.1:8080)';
        _backendSuccessMessage = null;
      });
      return;
    }

    try {
      await AppConfigService.instance.setBackendUrl(url);
      
      // Trigger connectivity check with new URL
      if (mounted) {
        final connectivityProvider = Provider.of<ConnectivityProvider>(context, listen: false);
        connectivityProvider.forceCheck();
      }
      
      setState(() {
        _backendSuccessMessage = 'Backend URL saved successfully!';
        _backendErrorMessage = null;
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _backendSuccessMessage = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _backendErrorMessage = 'Failed to save backend URL: $e';
        _backendSuccessMessage = null;
      });
    }
  }

  Future<void> _testConnection() async {
    final url = _backendUrlController.text.trim();
    
    if (url.isEmpty) {
      setState(() {
        _backendErrorMessage = 'Please enter a backend URL to test';
        _backendSuccessMessage = null;
      });
      return;
    }

    if (!AppConfigService.isValidBackendUrl(url)) {
      setState(() {
        _backendErrorMessage = 'Please enter a valid URL (e.g., http://127.0.0.1:8080)';
        _backendSuccessMessage = null;
      });
      return;
    }

    try {
      // Temporarily save the URL to test it
      final originalUrl = await AppConfigService.instance.getBackendUrl();
      await AppConfigService.instance.setBackendUrl(url);
      
      // Force a connectivity check
      if (mounted) {
        final connectivityProvider = Provider.of<ConnectivityProvider>(context, listen: false);
        connectivityProvider.forceCheck();
        
        // Wait a moment for the check to complete
        await Future.delayed(const Duration(seconds: 2));
        
        final isOnline = connectivityProvider.isOnline;
        
        if (isOnline) {
          setState(() {
            _backendSuccessMessage = 'Connection test successful!';
            _backendErrorMessage = null;
          });
        } else {
          setState(() {
            _backendErrorMessage = 'Connection test failed. Please check the URL and ensure the backend is running.';
            _backendSuccessMessage = null;
          });
          // Restore original URL if test failed
          await AppConfigService.instance.setBackendUrl(originalUrl);
        }
      }
    } catch (e) {
      setState(() {
        _backendErrorMessage = 'Connection test failed: $e';
        _backendSuccessMessage = null;
      });
    }
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
                final response = await MusicApiService.connectQobuz(username, password);
                
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

  void _showSpotifyConnectionDialog(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final streamingProvider = context.read<StreamingProvider>();
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Getting Spotify authorization URL...'),
          ],
        ),
      ),
    );

    try {
      // Get Spotify authorization URL
      final response = await SpotifyApiService.getSpotifyAuthUrl();
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      if (response.success && response.data != null) {
        // Open Spotify authorization URL in web browser
        final Uri authUri = Uri.parse(response.data!.authUrl);
        if (await canLaunchUrl(authUri)) {
          await launchUrl(
            authUri,
            mode: LaunchMode.externalApplication,
          );
          
          // Show success message
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Please complete authorization in your browser and return to the app.'),
              duration: Duration(seconds: 5),
            ),
          );
          
          // Refresh service status after a delay to allow for OAuth completion
          Future.delayed(const Duration(seconds: 3), () {
            streamingProvider.loadServiceStatus();
          });
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Could not open browser for Spotify authorization.'),
            ),
          );
        }
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Failed to get Spotify authorization URL: ${response.message}'),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error connecting to Spotify: $e'),
        ),
      );
    }
  }

  void _showThemeDialog(BuildContext context, ThemeProvider themeProvider) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.light_mode),
              title: const Text('Light'),
              subtitle: const Text('Always use light theme'),
              trailing: themeProvider.themeMode == ThemeMode.light
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                themeProvider.setThemeMode(ThemeMode.light);
                Navigator.of(dialogContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode),
              title: const Text('Dark'),
              subtitle: const Text('Always use dark theme'),
              trailing: themeProvider.themeMode == ThemeMode.dark
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                themeProvider.setThemeMode(ThemeMode.dark);
                Navigator.of(dialogContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: const Text('System'),
              subtitle: const Text('Follow system setting'),
              trailing: themeProvider.themeMode == ThemeMode.system
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                themeProvider.setThemeMode(ThemeMode.system);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
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
