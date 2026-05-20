import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/database.dart';

/// Global full-text search across every chat's message history. Backed
/// by the messages_fts virtual table created in the SQLite migration;
/// queries are ~O(1 ms) even on tens of thousands of messages.
class ChatSearchScreen extends ConsumerStatefulWidget {
  /// Callback fired when the user taps a hit — typically opens the chat
  /// and scrolls to the matching message. Kept as a callback rather
  /// than a direct nav so the chat screen owns the open semantics.
  final void Function(String chatId, String messageId) onHitTapped;

  const ChatSearchScreen({super.key, required this.onHitTapped});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<MessageSearchHit> _hits = const [];
  Timer? _debounce;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    // 180ms debounce: short enough to feel live, long enough that
    // a fast typist doesn't fire a query per keystroke.
    _debounce = Timer(const Duration(milliseconds: 180), () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final hits = await AppDatabase.instance.searchMessages(query, limit: 80);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search all chats...',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _runSearch,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear',
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _controller.text.trim().isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Search across every message in every chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                )
              : _hits.isEmpty
                  ? Center(
                      child: Text(
                        'No matches.',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final h = _hits[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: h.role == 'user'
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            child: Icon(
                              h.role == 'user'
                                  ? Icons.person_outline
                                  : Icons.smart_toy,
                              size: 18,
                              color: cs.onSurface,
                            ),
                          ),
                          title: Text(
                            h.chatTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _excerptAround(h.snippet, _controller.text),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatDate(h.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onHitTapped(h.chatId, h.messageId);
                          },
                        );
                      },
                    ),
    );
  }

  // Whitespace splitter hoisted to a static so we don't recompile this
  // regex per ListView item on every scroll frame.
  static final RegExp _wsSplitRe = RegExp(r'\s+');

  /// First whitespace-delimited token of [query], lowercased. Cached
  /// across all builder invocations for a given query so we only do the
  /// regex/split/lowercase once per search, not once per visible row.
  String _cachedQueryRaw = '';
  String _cachedNeedle = '';
  String _needleFor(String query) {
    if (query == _cachedQueryRaw) return _cachedNeedle;
    _cachedQueryRaw = query;
    final lower = query.toLowerCase();
    final firstSpace = lower.indexOf(_wsSplitRe);
    _cachedNeedle = firstSpace < 0 ? lower : lower.substring(0, firstSpace);
    return _cachedNeedle;
  }

  /// Trim the snippet to a window around the first query-term hit so
  /// long messages don't overrun the ListTile. Cheap; just a substring.
  String _excerptAround(String content, String query) {
    if (content.length <= 160) return content;
    final needle = _needleFor(query);
    if (needle.isEmpty) return content;
    final idx = content.toLowerCase().indexOf(needle);
    if (idx < 0) return content;
    final start = (idx - 40).clamp(0, content.length);
    final end = (idx + 120).clamp(0, content.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < content.length ? '…' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.month}/${dt.day}';
  }
}
