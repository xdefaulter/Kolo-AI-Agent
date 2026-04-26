import 'dart:convert';

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
        final Map<String, dynamic> tc = delta is Map<String, dynamic>
            ? delta
            : Map<String, dynamic>.from(delta as Map);

        final index = tc['index'] as int? ?? 0;
        _builders.putIfAbsent(index, () => _ToolCallBuilder());

        final builder = _builders[index]!;
        if (tc['id'] != null) builder.id = tc['id'] as String;
        
        final function = tc['function'] as Map<String, dynamic>? ?? {};
        if (function['name'] != null) builder.name = function['name'] as String;
        if (function['arguments'] != null) {
          builder.argumentsBuffer.write(function['arguments']);
        }
      }
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