import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/connectivity_service.dart';

class BackendStatusIndicator extends StatelessWidget {
  final bool showText;
  final bool compact;

  const BackendStatusIndicator({
    super.key,
    this.showText = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, connectivity, child) {
        final color = _getStatusColor(connectivity.status);
        final icon = _getStatusIcon(connectivity.status);
        
        if (compact) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: color,
                ),
                if (showText) ...[
                  const SizedBox(width: 4),
                  Text(
                    connectivity.statusText,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: color,
              ),
              if (showText) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      connectivity.statusText,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (connectivity.lastChecked != null)
                      Text(
                        'Last checked: ${_formatTime(connectivity.lastChecked!)}',
                        style: TextStyle(
                          color: color.withOpacity(0.7),
                          fontSize: 10,
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

  Color _getStatusColor(BackendStatus status) {
    switch (status) {
      case BackendStatus.online:
        return Colors.green;
      case BackendStatus.offline:
        return Colors.red;
      case BackendStatus.checking:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(BackendStatus status) {
    switch (status) {
      case BackendStatus.online:
        return Icons.cloud_done;
      case BackendStatus.offline:
        return Icons.cloud_off;
      case BackendStatus.checking:
        return Icons.cloud_sync;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}

// Extended status widget with more details
class BackendStatusCard extends StatelessWidget {
  const BackendStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, connectivity, child) {
        final color = _getStatusColor(connectivity.status);
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getStatusIcon(connectivity.status),
                      color: color,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Backend Status',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildStatusRow('Status', connectivity.statusText, color),
                if (connectivity.lastChecked != null)
                  _buildStatusRow(
                    'Last Checked', 
                    _formatDateTime(connectivity.lastChecked!),
                    Colors.grey[600],
                  ),
                if (connectivity.lastOnline != null)
                  _buildStatusRow(
                    'Last Online', 
                    _formatDateTime(connectivity.lastOnline!),
                    Colors.grey[600],
                  ),
                _buildStatusRow('Endpoint', 'http://127.0.0.1:8080', Colors.grey[600]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(String label, String value, Color? color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(BackendStatus status) {
    switch (status) {
      case BackendStatus.online:
        return Colors.green;
      case BackendStatus.offline:
        return Colors.red;
      case BackendStatus.checking:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(BackendStatus status) {
    switch (status) {
      case BackendStatus.online:
        return Icons.cloud_done;
      case BackendStatus.offline:
        return Icons.cloud_off;
      case BackendStatus.checking:
        return Icons.cloud_sync;
    }
  }

  String _formatDateTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} seconds ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else {
      return '${time.day}/${time.month}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
