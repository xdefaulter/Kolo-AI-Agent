import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/haptics.dart';

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
  final bool enterToSend;

  const InputBar({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onCancel,
    this.enterToSend = false,
  });

  @override
  State<InputBar> createState() => InputBarState();
}

class InputBarState extends State<InputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  List<ChatAttachment> _attachments = [];
  bool _isSending = false; // For send button bounce animation
  bool _isListening = false; // Mic button state (STT integration)
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // Debounced draft save
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), () {
      // Parent ChatScreen will handle this via callback
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Public method to set the controller text (for draft restoration)
  void setText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
  }

  /// Public method to get current text (for draft saving)
  String get currentText => _controller.text;

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (widget.isLoading) return;

    // Send button bounce animation
    setState(() => _isSending = true);
    Haptics.light();
    _controller.clear();
    final attachments = List<ChatAttachment>.from(_attachments);
    _attachments = [];
    widget.onSend(text, attachments: attachments.isEmpty ? null : attachments);

    // Reset bounce after animation
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _isSending = false);
    });
    _focusNode.requestFocus();
  }

  void _toggleMic() {
    Haptics.selection();
    setState(() => _isListening = !_isListening);
    // TODO: Wire up speech_to_text when STT is ready
    // For now, just toggle the visual state
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
          SnackBar(
            content: Text('Failed to pick image: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
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
          SnackBar(
            content: Text('Failed to pick file: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
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
                height: 76,
                margin: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final att = _attachments[index];
                        return _AttachmentChip(
                          attachment: att,
                          onRemove: () {
                            Haptics.light();
                            setState(() => _attachments.removeAt(index));
                          },
                        );
                      },
                    ),
                    // Count badge overlay
                    if (_attachments.length > 3)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '+${_attachments.length - 3}',
                              style: TextStyle(fontSize: 11, color: cs.onPrimary, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                  ],
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
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !widget.isLoading,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: widget.enterToSend ? TextInputAction.send : TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: widget.isLoading ? 'Thinking...' : 'Message Kolo...',
                      filled: true,
                      fillColor: cs.surfaceContainerLow.withValues(alpha: 0.7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                // Mic button (STT)
                if (!widget.isLoading)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.red.shade700 : cs.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _toggleMic,
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.white : cs.onSurface.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      tooltip: _isListening ? 'Stop listening' : 'Voice input',
                    ),
                  ),
                // Send / Cancel button
                if (widget.isLoading && widget.onCancel != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () {
                        Haptics.medium();
                        widget.onCancel!();
                      },
                      icon: const Icon(Icons.stop, color: Colors.white),
                      tooltip: 'Stop',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    ),
                  )
                else if (!widget.isLoading)
                  AnimatedScale(
                    scale: _isSending ? 0.85 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutBack,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _handleSend,
                        icon: Icon(Icons.send, color: cs.onPrimary, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        tooltip: 'Send',
                      ),
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
    Haptics.light();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachOption(
                    context: ctx,
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    color: Colors.blue,
                    onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
                  ),
                  _attachOption(
                    context: ctx,
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    color: Colors.green,
                    onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
                  ),
                  _attachOption(
                    context: ctx,
                    icon: Icons.insert_drive_file,
                    label: 'File',
                    color: Colors.orange,
                    onTap: () { Navigator.pop(ctx); _pickFile(); },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
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
        // Remove button — larger for better tap target
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: cs.error,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 14, color: cs.onError),
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