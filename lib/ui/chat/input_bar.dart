import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/haptics.dart';
import '../../core/stt_service.dart';

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

/// A single `@mention` suggestion rendered in the autocomplete popover.
/// Immutable + const-constructible so the overlay can reuse rows between
/// keystrokes without allocating.
class MentionSuggestion {
  /// Primary text shown in the row (e.g. the filename).
  final String label;

  /// Optional secondary text (e.g. parent directory), muted.
  final String? sublabel;

  /// What replaces the `@query` fragment when this row is tapped. Usually
  /// `@relative/path.dart`.
  final String insertText;

  /// Optional leading icon (defaults to a generic file icon).
  final IconData? icon;

  const MentionSuggestion({
    required this.label,
    required this.insertText,
    this.sublabel,
    this.icon,
  });
}

/// Called by [InputBar] when the user types `@<query>`. Implementations
/// should return at most 10-15 suggestions for a responsive popover.
/// Return an empty list to hide the popover.
typedef MentionLookup = Future<List<MentionSuggestion>> Function(String query);

class InputBar extends StatefulWidget {
  final Function(String, {List<ChatAttachment>? attachments}) onSend;
  final bool isLoading;
  final VoidCallback? onCancel;
  final bool enterToSend;
  final ValueChanged<String>? onDraftChanged;

  /// Optional autocomplete source for `@file` mentions. When null, the
  /// mention UI is fully disabled (no overhead — no listener work either).
  final MentionLookup? mentionLookup;

  /// When true, disables the IME's autocorrect + smart suggestions so
  /// tokens like `$ ls`, `@lib/main.dart`, and `/clear` don't get mangled.
  /// Defaults to false (chat screen wants helpful autocorrect for prose).
  final bool disableAutocorrect;

  /// Tapping the "library" button opens a saved-prompt picker. When
  /// null, the button is hidden entirely so apps that don't want the
  /// feature don't render an extra icon.
  final VoidCallback? onOpenPromptLibrary;

  const InputBar({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onCancel,
    this.enterToSend = false,
    this.onDraftChanged,
    this.mentionLookup,
    this.disableAutocorrect = false,
    this.onOpenPromptLibrary,
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
  bool _sttAvailable = false; // Whether STT is available on this device
  String _sttBuffer = ''; // Accumulated STT text for this session
  StreamSubscription? _sttPartialSub;
  StreamSubscription? _sttFinalSub;
  Timer? _draftTimer;

  // ── @mention state ───────────────────────────────────────────────
  Timer? _mentionDebounce;
  List<MentionSuggestion> _mentionResults = const [];
  int _mentionStart = -1; // cursor index of the `@` that triggered the popover
  int _mentionEnd = -1; // cursor end of current `@query` fragment
  String _mentionQuery = '';
  int _mentionRequestSeq = 0; // dropped-request guard — only latest wins

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _initStt();
  }

  Future<void> _initStt() async {
    final available = await SttService.instance.init();
    if (mounted) {
      setState(() => _sttAvailable = available);
    }
  }

  void _sttOnPartial(String text) {
    if (!mounted) return;
    // Show live transcription in the text field as user speaks
    final current = _controller.text;
    // Replace the STT portion at the end of current text
    final base = current.length > _sttBuffer.length
        ? current.substring(0, current.length - _sttBuffer.length)
        : '';
    setState(() {
      _sttBuffer = text;
      _controller.text = base + text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  void _sttOnFinal(String text) {
    if (!mounted) return;
    final current = _controller.text;
    // Strip the old partial STT text from the field, then append final result
    final base = current.length > _sttBuffer.length
        ? current.substring(0, current.length - _sttBuffer.length)
        : '';
    _controller.text = base + text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {
      _isListening = false;
      _sttBuffer = '';
    });
    _focusNode.requestFocus();
  }

  void _onTextChanged() {
    // Debounced draft save
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), () {
      widget.onDraftChanged?.call(_controller.text);
    });
    // Only compute mention state if a lookup is wired — skip entirely on
    // chat screen (mentionLookup == null) so the regex/scan isn't paid.
    if (widget.mentionLookup != null) {
      _updateMentionState();
    }
  }

  /// Word-characters that belong to an `@mention` query — letters, digits,
  /// and the common path separators so `@lib/ma` is one token.
  static bool _isMentionChar(int codeUnit) {
    // 0-9 → 0x30-0x39, A-Z → 0x41-0x5A, a-z → 0x61-0x7A
    // Plus `_`(0x5F), `.`(0x2E), `-`(0x2D), `/`(0x2F).
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        codeUnit == 0x5F ||
        codeUnit == 0x2E ||
        codeUnit == 0x2D ||
        codeUnit == 0x2F;
  }

  /// Scan backwards from the cursor for the nearest `@` to extract the
  /// current mention query. Returns null if the cursor isn't inside a
  /// mention token.
  (int start, int end, String query)? _currentMention() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > text.length) return null;
    // Walk back: allow mention chars, bail at anything else. The `@`
    // itself ends the scan.
    int i = cursor - 1;
    while (i >= 0) {
      final c = text.codeUnitAt(i);
      if (c == 0x40) {
        // '@' — must be at the start of the text or preceded by whitespace.
        if (i > 0) {
          final prev = text.codeUnitAt(i - 1);
          if (prev != 0x20 && prev != 0x0A && prev != 0x09) return null;
        }
        return (i, cursor, text.substring(i + 1, cursor));
      }
      if (!_isMentionChar(c)) return null;
      i--;
    }
    return null;
  }

  void _updateMentionState() {
    final mention = _currentMention();
    if (mention == null) {
      if (_mentionResults.isNotEmpty || _mentionStart != -1) {
        setState(() {
          _mentionResults = const [];
          _mentionStart = -1;
          _mentionEnd = -1;
          _mentionQuery = '';
        });
      }
      return;
    }
    final (start, end, query) = mention;
    _mentionStart = start;
    _mentionEnd = end;
    _mentionQuery = query;
    // Debounce so rapid typing doesn't thrash the lookup.
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 100), _runLookup);
  }

  Future<void> _runLookup() async {
    final lookup = widget.mentionLookup;
    if (lookup == null) return;
    final seq = ++_mentionRequestSeq;
    final results = await lookup(_mentionQuery);
    // Drop stale responses — user might have typed past the `@` already.
    if (!mounted || seq != _mentionRequestSeq) return;
    if (_mentionStart == -1) return;
    setState(() => _mentionResults = results);
  }

  void _selectMention(MentionSuggestion s) {
    if (_mentionStart < 0 || _mentionEnd < 0) return;
    final text = _controller.text;
    final replacement = '${s.insertText} ';
    final newText = text.replaceRange(_mentionStart, _mentionEnd, replacement);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: _mentionStart + replacement.length,
      ),
    );
    setState(() {
      _mentionResults = const [];
      _mentionStart = -1;
      _mentionEnd = -1;
      _mentionQuery = '';
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _mentionDebounce?.cancel();
    _sttPartialSub?.cancel();
    _sttFinalSub?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Public method to set the controller text (for draft restoration)
  void setText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
  }

  /// Public method to request focus on the input field
  void focus() {
    _focusNode.requestFocus();
  }

  /// Public method to get current text (for draft saving)
  String get currentText => _controller.text;

  /// Replace the composer contents with [text] and request focus. Used
  /// by the prompt-library + future `/command` inserters. Deliberately
  /// replaces rather than appends so the user sees the resolved prompt
  /// exactly as they'll send it.
  void insertText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _focusNode.requestFocus();
  }

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
    if (_isListening) {
      // Stop listening
      _sttPartialSub?.cancel();
      _sttFinalSub?.cancel();
      SttService.instance.stopListening();
      setState(() {
        _isListening = false;
        _sttBuffer = '';
      });
      _focusNode.requestFocus();
    } else {
      // Start listening
      _sttPartialSub?.cancel();
      _sttFinalSub?.cancel();
      _sttBuffer = '';
      _sttPartialSub = SttService.instance.partialResults.listen(_sttOnPartial);
      _sttFinalSub = SttService.instance.finalResults.listen(_sttOnFinal);
      SttService.instance.startListening().then((_) {
        if (!mounted) return;
        // If STT failed to start (e.g. permission denied)
        if (!SttService.instance.isListening) {
          _sttPartialSub?.cancel();
          _sttFinalSub?.cancel();
          setState(() => _isListening = false);
        }
      });
      setState(() => _isListening = true);
    }
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
      // Guard against the user navigating away (closing the chat drawer,
      // switching tab) while the image was being read. `readAsBytes` for
      // a large photo can take 100-300ms on a slow phone.
      if (!mounted) return;
      final base64 = _encodeBase64(bytes);
      setState(() {
        _attachments.add(
          ChatAttachment(
            name: xFile.name,
            mimeType: _mimeTypeForFile(xFile.name),
            base64Data: base64,
            filePath: xFile.path,
          ),
        );
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
        allowedExtensions: [
          'txt',
          'md',
          'json',
          'csv',
          'xml',
          'html',
          'css',
          'js',
          'py',
          'dart',
          'yaml',
          'yml',
          'log',
          'pdf',
        ],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      for (final file in result.files) {
        if (file.bytes == null && file.path == null) continue;
        final bytes =
            file.bytes ??
            (file.path != null ? await File(file.path!).readAsBytes() : null);
        if (bytes == null) continue;
        // Re-check mounted between awaits: multi-file picks can span
        // seconds, and the user may navigate away mid-loop.
        if (!mounted) return;
        final base64 = _encodeBase64(bytes);
        setState(() {
          _attachments.add(
            ChatAttachment(
              name: file.name,
              mimeType: _mimeTypeForFile(file.name),
              base64Data: base64,
              filePath: file.path,
            ),
          );
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
      'txt' ||
      'md' ||
      'log' ||
      'yaml' ||
      'yml' ||
      'css' ||
      'js' ||
      'py' ||
      'dart' => 'text/plain',
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
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // @mention autocomplete — renders only when a query is active.
            if (_mentionResults.isNotEmpty)
              _MentionOverlay(results: _mentionResults, onTap: _selectMention),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '+${_attachments.length - 3}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
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
                  icon: Icon(
                    Icons.attach_file,
                    color: widget.isLoading
                        ? cs.onSurface.withValues(alpha: 0.3)
                        : cs.primary,
                  ),
                  tooltip: 'Attach',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
                // Prompt library — optional, hidden when no callback wired.
                if (widget.onOpenPromptLibrary != null)
                  IconButton(
                    onPressed: widget.isLoading
                        ? null
                        : widget.onOpenPromptLibrary,
                    icon: Icon(
                      Icons.auto_awesome_outlined,
                      color: widget.isLoading
                          ? cs.onSurface.withValues(alpha: 0.3)
                          : cs.primary,
                    ),
                    tooltip: 'Prompt library',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 48,
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !widget.isLoading,
                    // Auto-grow from single line up to 6 for multi-paragraph
                    // prompts. Beyond that the TextField scrolls internally.
                    maxLines: 6,
                    minLines: 1,
                    autocorrect: !widget.disableAutocorrect,
                    enableSuggestions: !widget.disableAutocorrect,
                    textInputAction: widget.enterToSend
                        ? TextInputAction.send
                        : TextInputAction.newline,
                    style: TextStyle(color: cs.onSurface),
                    cursorColor: cs.primary,
                    decoration: InputDecoration(
                      hintText: widget.isLoading
                          ? 'Thinking...'
                          : 'Message Kolo...',
                      hintStyle: TextStyle(color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: cs.surfaceContainerLow.withValues(alpha: 0.7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      semanticCounterText: 'Message input field',
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                // Mic button (STT) — only show if speech recognition is available
                if (!widget.isLoading && _sttAvailable)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _isListening
                          ? Colors.red.shade700
                          : cs.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _toggleMic,
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening
                            ? Colors.white
                            : cs.onSurface.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: _isListening
                          ? 'Stop dictation'
                          : 'Dictate message',
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
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
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
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
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
                  color: Theme.of(
                    ctx,
                  ).colorScheme.onSurface.withValues(alpha: 0.2),
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
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  _attachOption(
                    context: ctx,
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    color: Colors.green,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  _attachOption(
                    context: ctx,
                    icon: Icons.insert_drive_file,
                    label: 'File',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickFile();
                    },
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
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
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// `@mention` autocomplete popover — sits directly above the input area.
/// Stateless; the parent [InputBar] owns all state, so this widget
/// rebuilds only when the filtered result list actually changes.
class _MentionOverlay extends StatelessWidget {
  final List<MentionSuggestion> results;
  final ValueChanged<MentionSuggestion> onTap;

  const _MentionOverlay({required this.results, required this.onTap});

  /// Cap the visible rows — long lists hurt scrolling and eat screen space.
  /// The lookup callback already limits results; this is belt-and-braces.
  static const _maxRows = 8;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = results.length > _maxRows
        ? results.sublist(0, _maxRows)
        : results;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: visible.length,
          itemBuilder: (context, i) => _MentionRow(
            suggestion: visible[i],
            onTap: () => onTap(visible[i]),
          ),
        ),
      ),
    );
  }
}

class _MentionRow extends StatelessWidget {
  final MentionSuggestion suggestion;
  final VoidCallback onTap;

  const _MentionRow({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              suggestion.icon ?? Icons.insert_drive_file_outlined,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (suggestion.sublabel != null &&
                      suggestion.sublabel!.isNotEmpty)
                    Text(
                      suggestion.sublabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
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
                // 68x68 logical px → ~3x DPR cap = 204 physical. Without
                // this the full-res photo (potentially 4032x3024 → ~48MB
                // ARGB) would be decoded just to render a tiny thumbnail.
                ? Image.file(
                    File(attachment.filePath!),
                    width: 68,
                    height: 68,
                    fit: BoxFit.cover,
                    cacheWidth: 204,
                    cacheHeight: 204,
                    filterQuality: FilterQuality.low,
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
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(11),
              ),
            ),
            child: Text(
              attachment.name.length > 8
                  ? '${attachment.name.substring(0, 5)}...'
                  : attachment.name,
              style: TextStyle(
                fontSize: 9,
                color: cs.onPrimary,
                fontWeight: FontWeight.w500,
              ),
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
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(8),
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
