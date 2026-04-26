import 'dart:convert';
import '../tools/tool_base.dart';
import '../tools/tool_registry.dart';
import '../permissions/permission_manager.dart';
import '../api/streaming_parser.dart';

/// Routes tool calls from the model to the appropriate tool executor.
///
/// The router also hosts per-session services that get threaded into the
/// [ToolContext] — specifically [subLlmCall] for prompt-kind custom tools
/// and its own [executeTool] (via a closure) for composed-kind custom
/// tools. These are nullable because the session wires them in after
/// construction; a null service just means tools that need it will
/// return a descriptive error instead of crashing.
class ToolRouter {
  final ToolRegistry registry;
  final PermissionManager permissionManager;

  /// Optional sub-LLM call. Null until the session wires it via
  /// [setSubLlmCall].
  ToolSubLlmCall? subLlmCall;

  ToolRouter({required this.registry, required this.permissionManager});

  /// Attach a sub-LLM executor. Safe to call at any time — subsequent
  /// tool executions will pick up the new value.
  void setSubLlmCall(ToolSubLlmCall? call) {
    subLlmCall = call;
  }

  /// Execute a resolved tool call, checking permissions first.
  Future<ToolResult> executeTool({
    required String toolName,
    required String toolCallId,
    required String argumentsJson,
    required String chatId,
  }) async {
    Map<String, dynamic> params;
    try {
      params = jsonDecode(argumentsJson) as Map<String, dynamic>;
    } catch (e) {
      return ToolResult.err('Invalid JSON arguments: $e');
    }
    return _executeToolWithParams(
      toolName: toolName,
      params: params,
      chatId: chatId,
    );
  }

  /// Internal: run a tool by already-decoded params. Exposed via the
  /// [ToolContext.runToolByName] callback so composed-kind custom tools
  /// can chain existing tools without re-serialising.
  Future<ToolResult> _executeToolWithParams({
    required String toolName,
    required Map<String, dynamic> params,
    required String chatId,
  }) async {
    final tool = registry.get(toolName);
    if (tool == null) {
      return ToolResult.err('Unknown tool: $toolName');
    }

    // Check permission
    final granted = await permissionManager.checkPermission(
      tool.permission,
      toolName: toolName,
      params: params,
    );
    if (!granted) {
      return ToolResult.err('Permission denied for tool: $toolName');
    }

    final context = ToolContext(
      chatId: chatId,
      permissionChecker: (perm) => permissionManager.checkPermission(
        perm,
        toolName: toolName,
        params: params,
      ),
      subLlmCall: subLlmCall,
      // Chained-tool execution uses the same router so permissions are
      // enforced uniformly. Composed tools can't bypass the user.
      runToolByName: (subName, subParams) => _executeToolWithParams(
        toolName: subName,
        params: subParams,
        chatId: chatId,
      ),
    );

    try {
      return await tool.execute(params, context);
    } catch (e) {
      return ToolResult.err('Tool execution error: $e');
    }
  }

  /// Execute multiple tool calls in parallel, deduplicating identical calls
  Future<List<ToolResult>> executeToolsParallel({
    required List<ResolvedToolCall> calls,
    required String chatId,
  }) async {
    // Dedup: group calls by (name, arguments). Use a record key so we
    // don't allocate a per-call concatenated string just to hash it.
    // Records compose hashCode/== from their fields automatically, which
    // matches the previous "${name}:${arguments}" semantics without the
    // intermediate allocation per call (was up to ~2× argument-size
    // bytes per call on large JSON tool args).
    final dedupMap = <(String, String), List<int>>{};
    for (var i = 0; i < calls.length; i++) {
      final key = (calls[i].name, calls[i].arguments);
      (dedupMap[key] ??= []).add(i);
    }

    final results = List<ToolResult?>.filled(calls.length, null);
    final futures = <Future<void>>[];

    for (final entry in dedupMap.entries) {
      final indices = entry.value;
      final call = calls[indices.first];
      futures.add(
        executeTool(
          toolName: call.name,
          toolCallId: call.id,
          argumentsJson: call.arguments,
          chatId: chatId,
        ).then((result) {
          for (final idx in indices) {
            results[idx] = result;
          }
        }),
      );
    }

    await Future.wait(futures);
    return results.cast<ToolResult>();
  }
}
