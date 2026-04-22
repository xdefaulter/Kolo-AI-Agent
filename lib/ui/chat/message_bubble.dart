import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final String? thinkingContent;
  final bool isStreaming;
  final List<String>? imagePaths;

  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.thinkingContent,
    this.isStreaming = false,
    this.imagePaths,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primary.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
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
                  ],
                ),
              ),
            // Show thinking section (collapsible)
            if (thinkingContent != null && thinkingContent!.isNotEmpty)
              _ThinkingSection(thinkingContent: thinkingContent!),
            // Show attached images
            if (imagePaths != null && imagePaths!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: imagePaths!.map((path) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(path),
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.broken_image, color: cs.onSurface.withValues(alpha: 0.3)),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            if (content.isEmpty && isStreaming)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  ),
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
              ),
            if (isStreaming && content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary),
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

/// Collapsible section showing model thinking/reasoning tokens
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
    // During streaming, auto-expand thinking. When finalized, default collapsed.
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
            onTap: () => setState(() => _expanded = !_expanded),
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
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: cs.primary.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
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
            ),
        ],
      ),
    );
  }
}