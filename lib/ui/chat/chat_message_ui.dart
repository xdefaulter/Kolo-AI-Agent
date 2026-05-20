/// UI-side message model for the chat screen. Distinct from the API-side
/// `ChatMessage` (which only carries API-serialisable fields) and from the
/// persisted `MessageEntry` (which has storage-specific fields).
///
/// Kept in its own file so it can be shared by the chat screen, the chat
/// drawer, message bubbles, and tests without pulling in the whole chat
/// screen file.
class ChatMessageUI {
  final String role;
  final String content;
  final String? thinkingContent;
  final String? toolName;
  final bool? toolSuccess;
  final bool isStreaming;
  final String? toolCallId;
  final List<String>? imagePaths;
  final DateTime? timestamp;

  /// True for real-time messages (used to trigger slide-in animation);
  /// false for messages loaded from history.
  final bool isNew;

  /// Database id for messages that have been persisted. Used by edit +
  /// retry flows to correlate a UI row with its SQLite row without
  /// re-reading the chat. Null for transient in-flight streaming.
  final String? dbId;

  /// True for assistant messages surfaced from an error path. Drives the
  /// inline "Retry" affordance in [MessageBubble].
  final bool isError;

  /// Optional persistence state. Currently only 'queued' is meaningful —
  /// used by the offline outbox flow so the bubble can show a "waiting
  /// to reconnect" indicator without the chat screen having to cross-
  /// reference a separate outbox provider on every rebuild.
  final String? status;

  /// Stable identity for list reconciliation. We try `dbId` first (it's
  /// the DB row id, globally unique and stable across rebuilds), then
  /// `toolCallId`, then fall back to "role:timestampMicros".
  String get id {
    if (dbId != null) return 'db:$dbId';
    if (toolCallId != null) return 'tc:$toolCallId';
    final ts = timestamp?.microsecondsSinceEpoch ?? 0;
    return '$role:$ts';
  }

  /// Pre-formatted `h:mm AM/PM` string. Computed lazily the first time
  /// it's asked for, then cached. Before this cache, chat streaming
  /// chunks triggered N `_formatTime(msg.timestamp)` calls per frame
  /// where N = visible messages; trivial per call, adds up at 60fps.
  String? _formattedTimestamp;
  String? get formattedTimestamp {
    final ts = timestamp;
    if (ts == null) return null;
    return _formattedTimestamp ??= _formatTimestamp(ts);
  }

  /// Pure function — exposed for tests.
  static String formatTimestampForTest(DateTime dt) => _formatTimestamp(dt);

  static String _formatTimestamp(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour12:$m $period';
  }

  ChatMessageUI({
    required this.role,
    required this.content,
    this.thinkingContent,
    this.toolName,
    this.toolSuccess,
    this.isStreaming = false,
    this.toolCallId,
    this.imagePaths,
    this.timestamp,
    this.isNew = false,
    this.dbId,
    this.isError = false,
    this.status,
  });
}
