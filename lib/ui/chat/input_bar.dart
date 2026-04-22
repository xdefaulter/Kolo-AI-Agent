import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// Attachment data (image or file)
class ChatAttachment {
  final String name;
  final String mimeType;
  final String base64Data;
  final String? filePath; // local path for display

  ChatAttachment({
    required this.name,
    required this.mimeType,
    required this.base64Data,
    this.filePath,
  });
}

class InputBar extends StatefulWidget {
  final Function(String, {List<ChatAttachment>? attachments}) onSend;
  final bool isLoading;
  final VoidCallback? onCancel;

  const InputBar({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onCancel,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  List<ChatAttachment> _attachments = [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (widget.isLoading) return;
    _controller.clear();
    final attachments = List<ChatAttachment>.from(_attachments);
    _attachments = [];
    widget.onSend(text, attachments: attachments.isEmpty ? null : attachments);
    _focusNode.requestFocus();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      final base64 = _encodeBase64(bytes);
      setState(() {
        _attachments.add(ChatAttachment(
          name: xFile.name,
          mimeType: _mimeTypeForFile(xFile.name),
          base64Data: base64,
          filePath: xFile.path,
        ));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'json', 'csv', 'xml', 'html', 'css', 'js', 'py', 'dart', 'yaml', 'yml', 'log', 'pdf'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      for (final file in result.files) {
        if (file.bytes == null && file.path == null) continue;
        final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
        if (bytes == null) continue;
        final base64 = _encodeBase64(bytes);
        setState(() {
          _attachments.add(ChatAttachment(
            name: file.name,
            mimeType: _mimeTypeForFile(file.name),
            base64Data: base64,
            filePath: file.path,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  String _encodeBase64(List<int> bytes) {
    return base64Encode(bytes);
  }

  String _mimeTypeForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'json' => 'application/json',
      'csv' => 'text/csv',
      'xml' => 'application/xml',
      'html' => 'text/html',
      'txt' || 'md' || 'log' || 'yaml' || 'yml' || 'css' || 'js' || 'py' || 'dart' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attachment previews
            if (_attachments.isNotEmpty)
              Container(
                height: 72,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final att = _attachments[index];
                    return _AttachmentChip(
                      attachment: att,
                      onRemove: () => setState(() => _attachments.removeAt(index)),
                    );
                  },
                ),
              ),
            Row(
              children: [
                // Attach button
                IconButton(
                  onPressed: widget.isLoading ? null : _showAttachMenu,
                  icon: Icon(Icons.attach_file, color: widget.isLoading ? cs.onSurface.withValues(alpha: 0.3) : cs.primary),
                  tooltip: 'Attach',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !widget.isLoading,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: widget.isLoading ? 'Thinking...' : 'Message Kolo...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.isLoading && widget.onCancel != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.stop, color: Colors.white),
                      tooltip: 'Stop',
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: widget.isLoading
                          ? cs.surfaceContainerHighest
                          : cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: widget.isLoading ? null : _handleSend,
                      icon: widget.isLoading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onSurface.withValues(alpha: 0.5),
                              ),
                            )
                          : Icon(Icons.send, color: cs.onPrimary),
                      color: cs.onPrimary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Gallery'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('File (text, PDF, code)'),
              onTap: () { Navigator.pop(ctx); _pickFile(); },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final ChatAttachment attachment;
  final VoidCallback onRemove;

  const _AttachmentChip({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isImage = attachment.mimeType.startsWith('image/');

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: isImage && attachment.filePath != null
                ? Image.file(
                    File(attachment.filePath!),
                    width: 68,
                    height: 68,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fileIcon(cs),
                  )
                : _fileIcon(cs),
          ),
        ),
        // Name tooltip
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: cs.scrim.withValues(alpha: 0.7),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
            ),
            child: Text(
              attachment.name.length > 8 ? '${attachment.name.substring(0, 5)}...' : attachment.name,
              style: TextStyle(fontSize: 9, color: cs.onPrimary, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Remove button
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: BoxDecoration(
                color: cs.error,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 16, color: cs.onError),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fileIcon(ColorScheme cs) {
    return Icon(
      Icons.insert_drive_file,
      color: cs.primary.withValues(alpha: 0.6),
      size: 28,
    );
  }
}

