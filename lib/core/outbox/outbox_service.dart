import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shape of a single item waiting to be sent. Serialised as JSON so a
/// process kill between "enqueue" and "send" doesn't lose the user's
/// message.
class OutboxItem {
  final String chatId;
  final String messageDbId;
  final String text;
  final DateTime queuedAt;

  OutboxItem({
    required this.chatId,
    required this.messageDbId,
    required this.text,
    required this.queuedAt,
  });

  Map<String, dynamic> toMap() => {
    'chatId': chatId,
    'messageDbId': messageDbId,
    'text': text,
    'queuedAt': queuedAt.toIso8601String(),
  };

  factory OutboxItem.fromMap(Map<String, dynamic> m) => OutboxItem(
    chatId: m['chatId'] as String,
    messageDbId: m['messageDbId'] as String,
    text: m['text'] as String,
    queuedAt: DateTime.parse(m['queuedAt'] as String),
  );
}

/// Thin, on-disk outbox for messages the user attempts to send while
/// offline. Stored as a JSON array in SharedPreferences — capped at
/// [maxItems] so a user stuck offline for a week doesn't end up with an
/// unbounded queue. Not a general-purpose durable queue; good enough
/// for retry-on-reconnect semantics.
class OutboxService {
  OutboxService._();
  static final OutboxService instance = OutboxService._();

  static const String _key = 'kolo_outbox_v1';

  /// Keep at most this many queued messages. On overflow, the oldest
  /// item is dropped so the most-recent attempts survive.
  static const int maxItems = 20;

  /// In-memory mirror of the persisted list. Populated on first read
  /// so subsequent enqueue / remove paths skip the JSON decode step
  /// entirely. The previous read-modify-write pattern decoded + encoded
  /// the entire array on every call — a hot loop while reconnecting
  /// flushes the queue.
  List<OutboxItem>? _cache;

  Future<List<OutboxItem>> all() async {
    final cached = _cache;
    if (cached != null) return List.unmodifiable(cached);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _cache = const [];
      return const [];
    }
    try {
      final list = jsonDecode(raw) as List;
      final parsed = list
          .map((e) => OutboxItem.fromMap(e as Map<String, dynamic>))
          .toList();
      _cache = parsed;
      return List.unmodifiable(parsed);
    } catch (e) {
      debugPrint('[outbox] corrupt state, resetting: $e');
      await prefs.remove(_key);
      _cache = const [];
      return const [];
    }
  }

  Future<void> enqueue(OutboxItem item) async {
    final current = await all();
    final next = [...current, item];
    if (next.length > maxItems) {
      next.removeRange(0, next.length - maxItems);
    }
    await _write(next);
  }

  /// Remove a specific item by messageDbId. Returns true if something
  /// was removed so callers can decide whether to reload.
  Future<bool> remove(String messageDbId) async {
    final current = await all();
    final next = current.where((i) => i.messageDbId != messageDbId).toList();
    if (next.length == current.length) return false;
    await _write(next);
    return true;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _cache = const [];
  }

  Future<void> _write(List<OutboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(items.map((i) => i.toMap()).toList()),
    );
    _cache = List.of(items);
  }
}
