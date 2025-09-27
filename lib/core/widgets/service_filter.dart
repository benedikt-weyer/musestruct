import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../music/providers/music_provider.dart';
import '../../music/providers/streaming_provider.dart';

class ServiceFilter extends StatelessWidget {
  const ServiceFilter({super.key});

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'qobuz':
        return const Color(0xFF00D4AA); // Qobuz green
      case 'spotify':
        return const Color(0xFF1DB954); // Spotify green
      case 'tidal':
        return const Color(0xFF000000); // Tidal black
      case 'apple_music':
        return const Color(0xFFFA243C); // Apple Music red
      case 'youtube_music':
        return const Color(0xFFFF0000); // YouTube red
      case 'deezer':
        return const Color(0xFF00C7B7); // Deezer cyan
      case 'server':
        return const Color(0xFF6B46C1); // Purple for server
      default:
        return Colors.grey[600]!;
    }
  }

  String _getServiceDisplayName(String serviceName) {
    switch (serviceName.toLowerCase()) {
      case 'qobuz':
        return 'Qobuz';
      case 'spotify':
        return 'Spotify';
      case 'tidal':
        return 'Tidal';
      case 'apple_music':
        return 'Apple Music';
      case 'youtube_music':
        return 'YouTube Music';
      case 'deezer':
        return 'Deezer';
      case 'server':
        return 'Server';
      default:
        return serviceName.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MusicProvider, StreamingProvider>(
      builder: (context, musicProvider, streamingProvider, child) {
        // Get connected services only
        final connectedServices = streamingProvider.services
            .where((service) => service.isConnected)
            .map((service) => service.name)
            .toList();

        // Debug logging removed to prevent console spam

        if (connectedServices.isEmpty) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_outlined,
                      color: Colors.orange[700],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No Connected Services',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to a streaming service to search for music.',
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontSize: 12,
                  ),
                ),
                if (streamingProvider.isLoading) ...[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                if (streamingProvider.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Error: ${streamingProvider.error}',
                    style: TextStyle(
                      color: Colors.red[700],
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with toggle and controls
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search Sources',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Toggle between single and multi-service search
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'All Sources',
                        style: TextStyle(
                          fontSize: 12,
                          color: musicProvider.useMultiServiceSearch 
                              ? Theme.of(context).primaryColor 
                              : Colors.grey[600],
                        ),
                      ),
                      Switch(
                        value: musicProvider.useMultiServiceSearch,
                        onChanged: (_) => musicProvider.toggleMultiServiceSearch(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              if (musicProvider.useMultiServiceSearch) ...[
                // Multi-service selection
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Select All / Clear All buttons
                    _buildActionChip(
                      context,
                      musicProvider.selectedServices.length == connectedServices.length
                          ? 'Clear All'
                          : 'Select All',
                      () {
                        if (musicProvider.selectedServices.length == connectedServices.length) {
                          musicProvider.clearServiceSelection();
                        } else {
                          musicProvider.selectAllServices();
                        }
                      },
                      isAction: true,
                    ),
                    // Individual service chips
                    ...connectedServices.map((serviceName) {
                      final isSelected = musicProvider.selectedServices.contains(serviceName);
                      return _buildServiceChip(
                        context,
                        serviceName,
                        isSelected,
                        () => musicProvider.toggleServiceSelection(serviceName),
                      );
                    }).toList(),
                  ],
                ),
                if (musicProvider.selectedServices.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Select at least one source to search',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ] else ...[
                // Single service selection (existing dropdown)
                Row(
                  children: [
                    const Text('Service: '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: musicProvider.selectedService,
                        isExpanded: true,
                        items: connectedServices.map((serviceName) {
                          return DropdownMenuItem<String>(
                            value: serviceName,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _getSourceColor(serviceName),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(_getServiceDisplayName(serviceName)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (String? value) {
                          if (value != null) {
                            musicProvider.selectService(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildServiceChip(
    BuildContext context,
    String serviceName,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final color = _getSourceColor(serviceName);
    final displayName = _getServiceDisplayName(serviceName);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? color.withOpacity(0.2) 
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? color 
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              displayName,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check,
                size: 14,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool isAction = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isAction 
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isAction 
                ? Theme.of(context).primaryColor
                : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isAction 
                ? Theme.of(context).primaryColor
                : Colors.grey[700],
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
