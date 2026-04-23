/// Manages conversation history with token budgeting
class ConversationManager {
  final List<ChatMessage> _messages = [];
  final int maxContextTokens;

  ConversationManager({this.maxContextTokens = 32000});

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  void addUserMessage(String content) {
    _messages.add(ChatMessage(role: 'user', content: content));
  }

  /// Add a user message with multimodal content (text + images)
  void addUserMessageMultimodal(List<Map<String, dynamic>> contentParts) {
    _messages.add(ChatMessage(role: 'user', content: '', multimodalContent: contentParts));
  }

  void addAssistantMessage(String content) {
    _messages.add(ChatMessage(role: 'assistant', content: content));
  }

  void addToolResultMessage(String toolCallId, String content) {
    _messages.add(ChatMessage(
      role: 'tool',
      content: content,
      toolCallId: toolCallId,
    ));
  }

  void addAssistantToolCallMessage(String content, List<Map<String, dynamic>> toolCalls) {
    _messages.add(ChatMessage(
      role: 'assistant',
      content: content,
      toolCalls: toolCalls,
    ));
  }

  /// Add a pre-built message (for loading from persistence)
  void addMessage(ChatMessage message) {
    _messages.add(message);
  }

  /// 3.6: Improved token estimation — accounts for whitespace splitting,
  /// special characters, and multi-byte characters (~1.3 tokens per word average).
  int _estimateTokens(String text) {
    if (text.isEmpty) return 0;
    // Word-based estimation is more accurate than char/4
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    // Add overhead for special tokens, tool call JSON structure
    return ((words * 1.3) + 4).ceil();
  }

  /// Get messages that fit within token budget, keeping system prompt + recent messages
  List<Map<String, dynamic>> getMessagesForApi({String? systemPrompt}) {
    final result = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      result.add({'role': 'system', 'content': systemPrompt});
    }

    final systemTokens = systemPrompt != null ? _estimateTokens(systemPrompt) : 0;
    final budget = maxContextTokens - systemTokens;

    final apiMessages = <Map<String, dynamic>>[];
    int usedTokens = 0;

    for (final msg in _messages.reversed) {
      final tokens = _estimateTokens(msg.content) + 50;
      if (usedTokens + tokens > budget) break;
      apiMessages.insert(0, msg.toApiFormat());
      usedTokens += tokens;
    }

    return [...result, ...apiMessages];
  }

  void clear() => _messages.clear();
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