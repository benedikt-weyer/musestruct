import 'package:flutter/material.dart';
import '../utils/url_utils.dart';

/// A widget that displays network images with automatic URL conversion
/// Converts relative URLs to full URLs using the configured backend URL
class NetworkImageWidget extends StatefulWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? errorWidget;
  final Widget? loadingWidget;
  final BorderRadius? borderRadius;

  const NetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.loadingWidget,
    this.borderRadius,
  });

  @override
  State<NetworkImageWidget> createState() => _NetworkImageWidgetState();
}

class _NetworkImageWidgetState extends State<NetworkImageWidget> {
  String? _fullUrl;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  @override
  void didUpdateWidget(NetworkImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadUrl();
    }
  }

  Future<void> _loadUrl() async {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      setState(() {
        _fullUrl = null;
        _isLoading = false;
        _hasError = true;
      });
      return;
    }

    try {
      final fullUrl = await UrlUtils.getFullUrl(widget.imageUrl);
      if (mounted) {
        setState(() {
          _fullUrl = fullUrl;
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fullUrl = null;
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Widget _buildErrorWidget() {
    return widget.errorWidget ??
        Icon(
          Icons.broken_image,
          color: Colors.grey[400],
        );
  }

  Widget _buildLoadingWidget() {
    return widget.loadingWidget ??
        Container(
          color: Colors.grey[200],
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isLoading) {
      child = _buildLoadingWidget();
    } else if (_hasError || _fullUrl == null || _fullUrl!.isEmpty) {
      child = _buildErrorWidget();
    } else {
      child = Image.network(
        _fullUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorWidget();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingWidget();
        },
      );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: child,
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: child,
    );
  }
}
