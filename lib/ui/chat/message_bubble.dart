import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'typing_indicator.dart';
import '../../core/haptics.dart';

class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final String? thinkingContent;
  final bool isStreaming;
  final List<String>? imagePaths;
  final String? timestamp; // e.g. "2:34 PM"

  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.thinkingContent,
    this.isStreaming = false,
    this.imagePaths,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: '${isUser ? "Your message" : "Kolo's message"}: ${content.isEmpty ? "thinking" : content}',
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? cs.primary.withValues(alpha: 0.2)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
            ),
            border: isUser
                ? null
                : Border.all(color: cs.outlineVariant.withValues(alpha: 0.15), width: 0.5),
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
                      thinkingContent != null && thinkingContent!.isNotEmpty ? 'Still thinking...' : 'Thinking...',
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13),
                    ),
                  ],
              )
              else
                MarkdownBody(
                  data: content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(color: cs.onSurface, fontSize: 15),
                    code: TextStyle(backgroundColor: cs.surface, color: cs.primary, fontSize: 13),
                    codeblockDecoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  // Add copy button for code blocks via custom builder
                  builders: {
                    'code': _CodeBlockBuilder(),
                  },
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
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    timestamp!,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated status dot for "agent is active"
class _StatusDot extends StatefulWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
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
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Image grid — 2 columns for multiple images
class _ImageGrid extends StatelessWidget {
  final List<String> imagePaths;
  const _ImageGrid({required this.imagePaths});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (imagePaths.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 240),
          child: Image.file(
            File(imagePaths.first),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 160,
              height: 120,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.broken_image, color: cs.onSurface.withValues(alpha: 0.3)),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: imagePaths.map((path) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: (MediaQuery.of(context).size.width * 0.35).clamp(100, 180),
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: (MediaQuery.of(context).size.width * 0.35).clamp(100, 180),
            height: 120,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.broken_image, color: cs.onSurface.withValues(alpha: 0.3)),
          ),
        ),
      )).toList(),
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
                  Icon(Icons.psychology_outlined, size: 14, color: cs.primary.withValues(alpha: 0.7)),
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

/// Markdown code block builder that adds a copy button
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget visitText(context, node) {
    // Inline code — just style it
    return const SizedBox.shrink();
  }
}

/// Code block with copy button — standalone widget for code blocks
class CodeBlockWithCopy extends StatelessWidget {
  final String code;
  const CodeBlockWithCopy({super.key, required this.code});

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
            child: SelectableText(
              code,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: cs.onSurface,
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.copy, size: 16, color: cs.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}