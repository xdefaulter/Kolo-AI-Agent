/// Default max context tokens for conversation budgeting
const int kDefaultMaxContextTokens = 32000;

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

  /// Estimate tokens for a chunk of text. Uses the higher of:
  ///   - word-based (~1.3 tokens/word) — good for English prose
  ///   - byte-based (~3.5 bytes/token) — kicks in for minified JSON, base64,
  ///     or tool payloads where whitespace-split gives almost no words.
  /// Using max() protects against the prose heuristic silently undercounting
  /// dense JSON and letting us blow past the provider's context limit.
  ///
  /// Allocation-free: counts whitespace transitions via codeUnitAt so no
  /// intermediate List<String> is created (previously O(n) alloc per call).
  int _estimateTokens(String text) {
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

  /// Get messages that fit within token budget, keeping system prompt + recent messages
  List<Map<String, dynamic>> getMessagesForApi({String? systemPrompt}) {
    final result = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      result.add({'role': 'system', 'content': systemPrompt});
    }

    final systemTokens = systemPrompt != null
        ? _estimateTokens(systemPrompt)
        : 0;
    final budget = maxContextTokens - systemTokens;

    // Build in reverse order with O(1) add(), then reverse once — avoids the
    // O(n) element shift that List.insert(0, …) causes on every iteration.
    final reversed = <Map<String, dynamic>>[];
    int usedTokens = 0;

    for (final msg in _messages.reversed) {
      final tokens = _estimateTokens(msg.content) + 50;
      if (usedTokens + tokens > budget) break;
      reversed.add(msg.toApiFormat());
      usedTokens += tokens;
    }

    return [...result, ...reversed.reversed];
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
