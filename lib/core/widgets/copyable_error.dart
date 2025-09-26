import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableErrorWidget extends StatelessWidget {
  final String errorMessage;
  final String? title;
  final EdgeInsetsGeometry? padding;
  final bool showIcon;

  const CopyableErrorWidget({
    super.key,
    required this.errorMessage,
    this.title,
    this.padding,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (showIcon) ...[
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title == null && showIcon) ...[
                Icon(
                  Icons.error_outline,
                  color: Colors.red.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SelectableText(
                  errorMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.red.shade800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _copyToClipboard(context, errorMessage),
                icon: Icon(
                  Icons.copy,
                  color: Colors.red.shade700,
                  size: 20,
                ),
                tooltip: 'Copy error message',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    
    // Show a brief confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Error message copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// Helper widget for showing copyable errors in dialogs
class CopyableErrorDialog extends StatelessWidget {
  final String errorMessage;
  final String title;

  const CopyableErrorDialog({
    super.key,
    required this.errorMessage,
    this.title = 'Error',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: CopyableErrorWidget(
        errorMessage: errorMessage,
        padding: EdgeInsets.zero,
        showIcon: false,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }

  static void show(BuildContext context, String errorMessage, {String title = 'Error'}) {
    showDialog(
      context: context,
      builder: (context) => CopyableErrorDialog(
        errorMessage: errorMessage,
        title: title,
      ),
    );
  }
}
