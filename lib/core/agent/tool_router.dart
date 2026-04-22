import 'dart:convert';
import '../tools/tool_base.dart';
import '../tools/tool_registry.dart';
import '../permissions/permission_manager.dart';
import '../api/streaming_parser.dart';

/// Routes tool calls from the model to the appropriate tool executor
class ToolRouter {
  final ToolRegistry registry;
  final PermissionManager permissionManager;

  ToolRouter({required this.registry, required this.permissionManager});

  /// Execute a resolved tool call, checking permissions first
  Future<ToolResult> executeTool({
    required String toolName,
    required String toolCallId,
    required String argumentsJson,
    required String chatId,
  }) async {
    final tool = registry.get(toolName);
    if (tool == null) {
      return ToolResult.err('Unknown tool: $toolName');
    }

    Map<String, dynamic> params;
    try {
      params = jsonDecode(argumentsJson) as Map<String, dynamic>;
    } catch (e) {
      return ToolResult.err('Invalid JSON arguments: $e');
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
    );

    try {
      return await tool.execute(params, context);
    } catch (e) {
      return ToolResult.err('Tool execution error: $e');
    }
  }

  /// Execute multiple tool calls in parallel
  Future<List<ToolResult>> executeToolsParallel({
    required List<ResolvedToolCall> calls,
    required String chatId,
  }) async {
    return Future.wait(
      calls.map((call) => executeTool(
            toolName: call.name,
            toolCallId: call.id,
            argumentsJson: call.arguments,
            chatId: chatId,
          )),
    );
  }
}