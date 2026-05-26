import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../playlists/providers/playlist_provider.dart';
import '../../../playlists/models/playlist.dart';

class CreatePlaylistDialog extends StatefulWidget {
  final Playlist? playlist;
  final bool isEdit;

  const CreatePlaylistDialog({
    super.key,
    this.playlist,
    this.isEdit = false,
  });

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isPublic = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit && widget.playlist != null) {
      _nameController.text = widget.playlist!.name;
      _descriptionController.text = widget.playlist!.description ?? '';
      _isPublic = widget.playlist!.isPublic;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? 'Edit Playlist' : 'Create Playlist'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Playlist Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.queue_music),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a playlist name';
                }
                return null;
              },
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Public Playlist'),
              subtitle: const Text('Make this playlist visible to others'),
              value: _isPublic,
              onChanged: (value) {
                setState(() {
                  _isPublic = value;
                });
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        Consumer<PlaylistProvider>(
          builder: (context, playlistProvider, child) {
            return ElevatedButton(
              onPressed: playlistProvider.isLoading ? null : _handleSubmit,
              child: playlistProvider.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.isEdit ? 'Update' : 'Create'),
            );
          },
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final playlistProvider = context.read<PlaylistProvider>();
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    bool success;
    if (widget.isEdit && widget.playlist != null) {
      success = await playlistProvider.updatePlaylist(
        playlistId: widget.playlist!.id,
        name: name,
        description: description,
        isPublic: _isPublic,
      );
    } else {
      success = await playlistProvider.createPlaylist(
        name: name,
        description: description,
        isPublic: _isPublic,
      );
    }

    if (mounted) {
      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEdit
                  ? 'Playlist updated successfully'
                  : 'Playlist created successfully',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              playlistProvider.error ??
                  (widget.isEdit
                      ? 'Failed to update playlist'
                      : 'Failed to create playlist'),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
