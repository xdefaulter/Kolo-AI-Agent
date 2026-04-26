/// Default max context tokens for conversation budgeting
const int kDefaultMaxContextTokens = 32000;

/// Token-count heuristic. Uses the larger of a word-based estimate
/// (~1.3 tokens/word, good for prose) and a byte-based floor
/// (~3.5 bytes/token, catches dense JSON/base64). Allocation-free —
/// walks code units in place; no `split()` / `List<String>`.
///
/// Exposed at top-level so [ChatMessage.estimatedContentTokens] can
/// memoise its result (the message content is final, so the answer
/// can never go stale).
int estimateTextTokens(String text) {
  if (text.isEmpty) return 0;
  int words = 0;
  bool inWord = false;
  for (int i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    final isWs = c == 32 || c == 9 || c == 10 || c == 13;
    if (!isWs && !inWord) {
      words++;
      inWord = true;
    } else if (isWs) {
      inWord = false;
    }
  }
  final wordEstimate = ((words * 1.3) + 4).ceil();
  final byteEstimate = (text.length / 3.5).ceil();
  return wordEstimate > byteEstimate ? wordEstimate : byteEstimate;
}

/// Manages conversation history with token budgeting
class ConversationManager {
  final List<ChatMessage> _messages = [];
  final int maxContextTokens;

  /// Max messages kept in memory — older messages are pruned
  static const _maxInMemoryMessages = 200;

  ConversationManager({this.maxContextTokens = kDefaultMaxContextTokens});

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  void addUserMessage(String content) {
    _messages.add(ChatMessage(role: 'user', content: content));
  }

  /// Add a user message with multimodal content (text + images)
  void addUserMessageMultimodal(List<Map<String, dynamic>> contentParts) {
    _messages.add(
      ChatMessage(role: 'user', content: '', multimodalContent: contentParts),
    );
  }

  void addAssistantMessage(String content) {
    _messages.add(ChatMessage(role: 'assistant', content: content));
  }

  void addToolResultMessage(String toolCallId, String content) {
    _messages.add(
      ChatMessage(role: 'tool', content: content, toolCallId: toolCallId),
    );
  }

  void addAssistantToolCallMessage(
    String content,
    List<Map<String, dynamic>> toolCalls,
  ) {
    _messages.add(
      ChatMessage(role: 'assistant', content: content, toolCalls: toolCalls),
    );
  }

  /// Add a pre-built message (for loading from persistence)
  void addMessage(ChatMessage message) {
    _messages.add(message);
    _pruneIfNeeded();
  }

  /// Prune oldest messages if list exceeds cap
  void _pruneIfNeeded() {
    if (_messages.length > _maxInMemoryMessages) {
      _messages.removeRange(0, _messages.length - _maxInMemoryMessages);
    }
  }

  /// Get messages that fit within token budget, keeping system prompt + recent messages
  List<Map<String, dynamic>> getMessagesForApi({String? systemPrompt}) {
    final result = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      result.add({'role': 'system', 'content': systemPrompt});
    }

    final systemTokens = systemPrompt != null
        ? estimateTextTokens(systemPrompt)
        : 0;
    final budget = maxContextTokens - systemTokens;

    // Build in reverse order with O(1) add(), then reverse once — avoids the
    // O(n) element shift that List.insert(0, …) causes on every iteration.
    final reversed = <Map<String, dynamic>>[];
    int usedTokens = 0;

    for (final msg in _messages.reversed) {
      // ChatMessage memoises its token estimate (content is final), so a
      // 200-message conversation pays the codeUnitAt walk exactly once
      // per message across the lifetime of the session — not once per
      // turn as the prior `_estimateTokens(msg.content)` call did.
      final tokens = msg.estimatedContentTokens + 50;
      if (usedTokens + tokens > budget) break;
      reversed.add(msg.toApiFormat());
      usedTokens += tokens;
    }

    // Append in reverse-of-reverse (i.e. chronological) order directly
    // into `result`. Previous `[...result, ...reversed.reversed]` form
    // allocated a fresh list and copied both source iterables; addAll
    // grows `result` in-place so we pay one copy total.
    for (int i = reversed.length - 1; i >= 0; i--) {
      result.add(reversed[i]);
    }
    return result;
  }

  void clear() => _messages.clear();

  /// Drop every message from [index] onwards (inclusive). Used by the
  /// edit flow to roll the conversation back to just before the edited
  /// message. [index] is clamped; negative or past-end values are no-ops.
  void truncateFrom(int index) {
    if (index < 0 || index >= _messages.length) return;
    _messages.removeRange(index, _messages.length);
  }

  /// Drop trailing assistant / tool / tool-call messages until the last
  /// remaining message is a user message. Used by the retry flow so the
  /// next run re-processes the same user turn. No-op if the tail is
  /// already a user message (or empty).
  void popTrailingAssistantTurn() {
    while (_messages.isNotEmpty && _messages.last.role != 'user') {
      _messages.removeLast();
    }
  }
}

class ChatMessage {
  final String role;
  final String content;
  final String? toolCallId;
  final List<Map<String, dynamic>>? toolCalls;
  final List<Map<String, dynamic>>? multimodalContent; // for vision messages

  ChatMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls,
    this.multimodalContent,
  });

  /// Lazy memoised token estimate over [content]. Safe to cache because
  /// [content] is final — value never goes stale. Call sites in the
  /// conversation budgeter previously re-walked the string on every
  /// `getMessagesForApi` invocation; with N=200 messages and multi-KB
  /// payloads that was MBs of redundant work per turn.
  int? _cachedTokens;
  int get estimatedContentTokens =>
      _cachedTokens ??= estimateTextTokens(content);

  Map<String, dynamic> toApiFormat() {
    final map = <String, dynamic>{'role': role};
    if (multimodalContent != null && multimodalContent!.isNotEmpty) {
      map['content'] = multimodalContent;
    } else if (content.isNotEmpty) {
      map['content'] = content;
    }
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (toolCalls != null) map['tool_calls'] = toolCalls;
    return map;
  }
}
