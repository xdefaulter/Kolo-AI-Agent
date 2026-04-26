import 'dart:convert';

import 'openai_client.dart' show ToolCallDelta;

/// Parses streaming SSE data to reconstruct complete tool calls
class StreamingParser {
  final Map<int, _ToolCallBuilder> _builders = {};

  void processChunk({
    required String content,
    List<dynamic>? toolCallDeltas,
  }) {
    // NOTE: agent_loop maintains its own contentBuffer; we only care
    // about reconstructing tool-call argument strings here. Skipping
    // the redundant per-chunk write saves an O(n) memcpy + heap
    // pressure on every SSE chunk for the entire stream.
    if (toolCallDeltas != null) {
      for (final delta in toolCallDeltas) {
        // Hot path: SSE tool-call deltas arrive on every chunk for
        // tool-calling models. The Dart JSON decoder always emits
        // `Map<String, dynamic>`, so the `is` check passes and the
        // `Map.from` fallback is dead code in practice — keep it for
        // safety but read fields via `Map` to avoid even the type
        // check overhead, and never copy the map.
        final Map tc = delta as Map;

        final index = tc['index'] as int? ?? 0;
        final builder = _builders.putIfAbsent(index, _ToolCallBuilder.new);

        final id = tc['id'];
        if (id != null) builder.id = id as String;

        final function = tc['function'] as Map?;
        if (function != null) {
          final name = function['name'];
          if (name != null) builder.name = name as String;
          final args = function['arguments'];
          if (args != null) builder.argumentsBuffer.write(args);
        }
      }
    }
  }

  /// Typed fast-path that avoids the Map<->ToolCallDelta round-trip.
  ///
  /// agent_loop receives `List<ToolCallDelta>` from `ChatStreamChunk` and
  /// previously rebuilt a `List<Map<String, dynamic>>` per chunk just to
  /// hand it back to [processChunk] (which then read the fields off the
  /// Map). For a long tool-calling turn that's one wrapper Map + one
  /// nested function Map allocated per delta per SSE chunk for nothing.
  /// This overload reads the typed fields directly.
  void processToolCallDeltas(Iterable<ToolCallDelta> deltas) {
    for (final tc in deltas) {
      final index = tc.index ?? 0;
      final builder = _builders.putIfAbsent(index, _ToolCallBuilder.new);
      final id = tc.id;
      if (id != null) builder.id = id;
      final name = tc.name;
      if (name != null) builder.name = name;
      final args = tc.arguments;
      if (args != null) builder.argumentsBuffer.write(args);
    }
  }

  List<ResolvedToolCall> resolveToolCalls() {
    return _builders.entries.map((e) {
      final builder = e.value;
      return ResolvedToolCall(
        id: builder.id ?? 'call_${e.key}',
        name: builder.name ?? '',
        arguments: builder.argumentsBuffer.toString(),
      );
    }).toList();
  }

  void reset() {
    _builders.clear();
  }
}

class _ToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer argumentsBuffer = StringBuffer();
}

class ResolvedToolCall {
  final String id;
  final String name;
  final String arguments; // JSON string

  ResolvedToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// OpenAI-shape `{id, type, function: {name, arguments}}` map.
  /// Built lazily and cached: the same map is needed by `agent_loop`
  /// (to append the assistant-with-tool-calls turn to the API message
  /// list) AND by `agent_session` (to mirror that turn into the
  /// conversation manager). Without memoisation a single tool call
  /// pays for two outer + two inner Map allocations every turn — and
  /// retryLastTurn re-pays them again.
  Map<String, dynamic>? _apiFormat;
  Map<String, dynamic> toApiFormat() => _apiFormat ??= {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
      };

  Map<String, dynamic> parseArguments() {
    if (arguments.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(
        jsonDecode(arguments) as Map,
      );
    } catch (_) {
      return {};
    }
  }
}