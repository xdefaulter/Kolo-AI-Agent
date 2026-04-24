import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:highlight/highlight.dart' as hl;
import 'typing_indicator.dart';
import '../../core/haptics.dart';

class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final String? thinkingContent;
  final bool isStreaming;
  final List<String>? imagePaths;
  final String? timestamp; // e.g. "2:34 PM"

  /// Long-press on the bubble. Used by the chat screen to surface the
  /// edit / copy / delete menu on user messages. Leave null to disable.
  final VoidCallback? onLongPress;

  /// When true, render a small "queued, waiting to reconnect" indicator.
  /// Only applied to user bubbles; orthogonal to [isStreaming].
  final bool isQueued;

  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.thinkingContent,
    this.isStreaming = false,
    this.imagePaths,
    this.timestamp,
    this.onLongPress,
    this.isQueued = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final cs = Theme.of(context).colorScheme;

    // 2.7: Use LayoutBuilder instead of MediaQuery.of to avoid rebuilds on keyboard/rotation
    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          label:
              '${isUser ? "Your message" : "Kolo's message"}: ${content.isEmpty ? "thinking" : content}',
          child: Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              onLongPress: onLongPress == null
                  ? null
                  : () {
                      Haptics.medium();
                      onLongPress!();
                    },
              child: Container(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
              decoration: BoxDecoration(
                color: isUser
                    ? cs.primary.withValues(alpha: 0.2)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.smart_toy, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Kolo',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          // Agent status dot
                          if (isStreaming) ...[
                            const SizedBox(width: 6),
                            _StatusDot(color: cs.primary),
                          ],
                        ],
                      ),
                    ),
                  // Show thinking section (collapsible with animation)
                  if (thinkingContent != null && thinkingContent!.isNotEmpty)
                    _ThinkingSection(thinkingContent: thinkingContent!),
                  // Show attached images — 2-column grid
                  if (imagePaths != null && imagePaths!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ImageGrid(imagePaths: imagePaths!),
                    ),
                  // Streaming / content
                  if (content.isEmpty && isStreaming)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TypingIndicator(color: cs.primary, dotSize: 7),
                        const SizedBox(width: 8),
                        Text(
                          thinkingContent != null && thinkingContent!.isNotEmpty
                              ? 'Still thinking...'
                              : 'Thinking...',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  else
                    MarkdownBody(
                      data: content,
                      // User bubbles rely on a parent long-press to open
                      // the edit menu. SelectableText would swallow that
                      // gesture, so we keep user messages non-selectable
                      // and provide "Copy" inside the action menu instead.
                      // Assistant bubbles stay selectable — copying a
                      // chunk of a long answer is the common case.
                      selectable: !isUser,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: cs.onSurface, fontSize: 15),
                        code: TextStyle(
                          backgroundColor: cs.surface,
                          color: cs.primary,
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      builders: {'pre': _CodeBlockBuilder()},
                    ),
                  // Streaming indicator at end of content
                  if (isStreaming && content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TypingIndicator(color: cs.primary, dotSize: 5),
                        ],
                      ),
                    ),
                  // Timestamp
                  if (timestamp != null && !isStreaming)
                    Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          timestamp!,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ),
                  // "Waiting to reconnect" indicator for queued user messages
                  if (isQueued && !isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 11,
                              color: cs.onSurface.withValues(alpha: 0.45),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'waiting to reconnect',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              ),
            ),
          ),
        );
      },
    ); // LayoutBuilder
  }
}

/// Animated status dot for "agent is active"
class _StatusDot extends StatefulWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Image grid — 2 columns for multiple images, tap to fullscreen
class _ImageGrid extends StatelessWidget {
  final List<String> imagePaths;
  const _ImageGrid({required this.imagePaths});

  void _openFullscreen(BuildContext context, String path) {
    Haptics.selection();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.black87,
          body: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  child: Center(
                    child: Hero(
                      tag: 'image_$path',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        // Cap decode size to 1920 — matches the image picker's
                        // max output resolution (maxWidth: 1920 in _pickImage).
                        // On mobile this keeps a 4032x3024 photo from being
                        // decoded into a ~48MB ARGB buffer.
                        child: Image.file(
                          File(path),
                          fit: BoxFit.contain,
                          cacheWidth: 1920,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            size: 48,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (imagePaths.length == 1) {
      return GestureDetector(
        onTap: () => _openFullscreen(context, imagePaths.first),
        child: Hero(
          tag: 'image_${imagePaths.first}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 240),
              // Bubble thumbnail maxes at 240x200 logical px. Decode at
              // ~3x device pixel ratio (cap 720) so the thumbnail stays
              // crisp on high-DPI screens without decoding the full photo.
              child: Image.file(
                File(imagePaths.first),
                fit: BoxFit.cover,
                cacheWidth: 720,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => Container(
                  width: 160,
                  height: 120,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.broken_image,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: imagePaths
          .map(
            (path) => GestureDetector(
              onTap: () => _openFullscreen(context, path),
              child: Hero(
                tag: 'image_$path',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  // Grid tile is 140x120 logical px — decode at ~3x DPR.
                  child: Image.file(
                    File(path),
                    width: 140.0,
                    height: 120,
                    fit: BoxFit.cover,
                    cacheWidth: 420,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => Container(
                      width: 140.0,
                      height: 120,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.broken_image,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Collapsible section showing model thinking/reasoning tokens — with animation
class _ThinkingSection extends StatefulWidget {
  final String thinkingContent;
  const _ThinkingSection({required this.thinkingContent});

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              Haptics.selection();
              setState(() => _expanded = !_expanded);
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _expanded ? 'Thinking' : 'Thought for a moment',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.primary.withValues(alpha: 0.8),
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.expand_more,
                      size: 16,
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.thinkingContent,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Markdown code block builder that adds syntax highlighting
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitText(text, preferredStyle) {
    return CodeBlockWithCopy(code: text.textContent);
  }
}

/// Code block with syntax highlighting and copy button
class CodeBlockWithCopy extends StatelessWidget {
  final String code;
  final String? language;
  const CodeBlockWithCopy({super.key, required this.code, this.language});

  /// Map of common language aliases to highlight.js mode names
  static const _langMap = {
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'rb': 'ruby',
    'sh': 'bash',
    'yml': 'yaml',
    'md': 'markdown',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: _SyntaxHighlight(code: code, language: language),
          ),
        ),
        // Language label
        if (language != null && language!.isNotEmpty)
          Positioned(
            top: 4,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                language!,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                Haptics.light();
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Code copied'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Syntax-highlighted code widget using the highlight package.
///
/// Perf: the highlight.parse() call is moderately expensive (lexer scan
/// over the whole snippet). Before caching, every parent rebuild re-parsed
/// the same code — so a streaming chat screen would re-parse the same
/// visible code blocks dozens of times per second. Now we parse once in
/// [initState] / [didUpdateWidget] and reuse the `nodes` list, so only
/// the span-building runs per rebuild (and that's cheap: a tree walk that
/// reuses the class-level `TextStyle` instances below).
class _SyntaxHighlight extends StatefulWidget {
  final String code;
  final String? language;
  const _SyntaxHighlight({required this.code, this.language});

  @override
  State<_SyntaxHighlight> createState() => _SyntaxHighlightState();
}

class _SyntaxHighlightState extends State<_SyntaxHighlight> {
  List<hl.Node> _nodes = const [];

  // Cached TextSpan tree — reused across builds when nodes and theme are stable.
  // Invalidated in _reparse() (new nodes) and in build() when theme brightness changes.
  TextSpan? _cachedSpans;
  Brightness? _cachedBrightness;

  @override
  void initState() {
    super.initState();
    _reparse();
  }

  @override
  void didUpdateWidget(covariant _SyntaxHighlight old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.language != widget.language) {
      _reparse();
    }
  }

  void _reparse() {
    final lang = _resolveLanguage(widget.language);
    try {
      _nodes =
          hl.highlight.parse(widget.code, language: lang).nodes ?? const [];
    } catch (_) {
      _nodes = [hl.Node(value: widget.code)];
    }
    _cachedSpans = null; // invalidate span cache whenever nodes change
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_cachedSpans == null || _cachedBrightness != cs.brightness) {
      _cachedBrightness = cs.brightness;
      _cachedSpans = _buildSpans(_nodes, cs);
    }
    return RichText(text: _cachedSpans!, softWrap: true);
  }

  String _resolveLanguage(String? lang) {
    if (lang == null || lang.isEmpty) return 'plaintext';
    final lower = lang.toLowerCase();
    return CodeBlockWithCopy._langMap[lower] ?? lower;
  }

  TextSpan _buildSpans(List<hl.Node> nodes, ColorScheme cs) {
    final children = nodes.map((node) {
      // Leaf text node: has value but no children
      if (node.children == null && node.value != null) {
        final style = node.className != null
            ? _styleForClass(node.className, cs)
            : TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: cs.onSurface,
              );
        return TextSpan(text: node.value, style: style);
      }
      // Element node: has children and possibly a className
      if (node.children != null) {
        final style = _styleForClass(node.className, cs);
        final childSpans = _buildSpans(node.children!, cs).children ?? [];
        return TextSpan(children: childSpans, style: style);
      }
      // Fallback: node with value and no children (plain text)
      if (node.value != null) {
        return TextSpan(
          text: node.value,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: cs.onSurface,
          ),
        );
      }
      return const TextSpan();
    }).toList();
    return TextSpan(children: children);
  }

  // Pre-built style maps to avoid allocating TextStyle on every build
  static const _darkStyles = <String, TextStyle>{
    'keyword': TextStyle(
      color: Color(0xFFC678DD),
      fontWeight: FontWeight.bold,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'string': TextStyle(
      color: Color(0xFF98C379),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'number': TextStyle(
      color: Color(0xFFD19A66),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'comment': TextStyle(
      color: Color(0xFF5C6370),
      fontStyle: FontStyle.italic,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'function': TextStyle(
      color: Color(0xFF61AFEF),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'title': TextStyle(
      color: Color(0xFF61AFEF),
      fontWeight: FontWeight.bold,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'params': TextStyle(
      color: Color(0xFFE06C75),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'built_in': TextStyle(
      color: Color(0xFFE5C07B),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'attr': TextStyle(
      color: Color(0xFFD19A66),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'literal': TextStyle(
      color: Color(0xFFD19A66),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'type': TextStyle(
      color: Color(0xFFE5C07B),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
  };
  static const _lightStyles = <String, TextStyle>{
    'keyword': TextStyle(
      color: Color(0xFF7B30A0),
      fontWeight: FontWeight.bold,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'string': TextStyle(
      color: Color(0xFF2E7D32),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'number': TextStyle(
      color: Color(0xFFB8600D),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'comment': TextStyle(
      color: Color(0xFF8E8E8E),
      fontStyle: FontStyle.italic,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'function': TextStyle(
      color: Color(0xFF1565C0),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'title': TextStyle(
      color: Color(0xFF1565C0),
      fontWeight: FontWeight.bold,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'params': TextStyle(
      color: Color(0xFFC62828),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'built_in': TextStyle(
      color: Color(0xFF9E6D00),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'attr': TextStyle(
      color: Color(0xFFB8600D),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'literal': TextStyle(
      color: Color(0xFFB8600D),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    'type': TextStyle(
      color: Color(0xFF9E6D00),
      fontSize: 13,
      fontFamily: 'monospace',
    ),
  };

  TextStyle _styleForClass(String? className, ColorScheme cs) {
    final styles = cs.brightness == Brightness.dark
        ? _darkStyles
        : _lightStyles;
    return styles[className] ??
        TextStyle(color: cs.onSurface, fontSize: 13, fontFamily: 'monospace');
  }
}
