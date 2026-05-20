import '../tools/tool_base.dart';
import 'memory_service.dart';

/// `remember_this` — agent-authored memory creation.
///
/// Gated behind the agent-can-create-memories Settings toggle. Permission
/// is `sensitive` (not `dangerous`) because creating a memory is
/// recoverable: the user can review + delete from Settings → Memories,
/// and nothing outside the app ever sees the content.
class RememberThisTool extends KoloTool {
  /// Called after a successful create so the Riverpod memories provider
  /// re-reads the store. Injected rather than held as a Ref, same
  /// pattern as [CreateToolTool.onChange].
  final Future<void> Function() onChange;

  RememberThisTool({required this.onChange});

  @override
  String get name => 'remember_this';

  @override
  String get description =>
      'Save a long-lived memory about the user. Memories persist across '
      'chats and get appended to your system prompt on relevant turns. '
      'USE SPARINGLY — only save facts/preferences the user has stated '
      'or clearly implied. Never save transient task details; those belong '
      'in the conversation. Kinds: "preference" (how they like to work), '
      '"fact" (stable info about them/their work), "goal" (ongoing objective).';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'kind': {
        'type': 'string',
        'enum': ['preference', 'fact', 'goal', 'note'],
        'description': 'Category of memory.',
      },
      'content': {
        'type': 'string',
        'description':
            'One concise sentence. Prefer 1st-person-about-user voice, '
            'e.g. "The user prefers tabs over spaces". Max ~200 chars.',
      },
    },
    'required': ['kind', 'content'],
  };

  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final kind = (params['kind'] as String?)?.trim() ?? 'note';
    final content = (params['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) {
      return ToolResult.err('content is required');
    }
    if (content.length > 500) {
      return ToolResult.err(
        'content is too long (${content.length} chars, max 500). Split into multiple memories.',
      );
    }
    final approved = await context.permissionChecker(ToolPermission.sensitive);
    if (!approved) return ToolResult.err('User declined memory save.');
    final entry = await MemoryService.instance.create(
      kind: kind,
      content: content,
      sourceChatId: context.chatId,
    );
    await onChange();
    return ToolResult.ok(
      'Saved memory ${entry.id} ($kind).',
      metadata: {'id': entry.id, 'kind': kind},
    );
  }
}

/// `recall_memories` — read-only search over the memory store. Returns
/// up to [kMemoryRecallCap] best matches. Cheap and safe, so permission
/// is `safe` (no user prompt).
class RecallMemoriesTool extends KoloTool {
  @override
  String get name => 'recall_memories';

  @override
  String get description =>
      'Search your long-lived memory store for facts/preferences relevant '
      "to a query. Use when you suspect prior context would help and it's "
      'not already in the current conversation. Empty results mean nothing '
      'matched — NOT a system failure.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'Natural-language query. Can be empty to get the most-recent memories.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Max results (default 6, cap 20).',
      },
    },
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final query = (params['query'] as String?) ?? '';
    final limitRaw = params['limit'];
    final limit = (limitRaw is int)
        ? limitRaw.clamp(1, 20)
        : kMemoryRecallCap;
    final memories = await MemoryService.instance.recall(query, limit: limit);
    if (memories.isEmpty) {
      return ToolResult.ok('(no matching memories)');
    }
    final lines = memories
        .map(
          (m) =>
              '${m.id}\t${m.kind}\t${m.content.replaceAll("\n", " ")}',
        )
        .join('\n');
    return ToolResult.ok(lines);
  }
}

/// `forget_memory` — delete a memory by id. Dangerous only in the sense
/// that it's irreversible; confirmation dialog surfaces the id + content.
class ForgetMemoryTool extends KoloTool {
  final Future<void> Function() onChange;

  ForgetMemoryTool({required this.onChange});

  @override
  String get name => 'forget_memory';

  @override
  String get description =>
      'Delete a saved memory by id. Use when the user says "forget that", '
      '"that was wrong", or similar. Irreversible.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'id': {
        'type': 'string',
        'description':
            'Memory id returned by recall_memories / remember_this.',
      },
    },
    'required': ['id'],
  };

  @override
  ToolPermission get permission => ToolPermission.dangerous;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final id = (params['id'] as String?)?.trim();
    if (id == null || id.isEmpty) return ToolResult.err('id is required');
    final approved = await context.permissionChecker(ToolPermission.dangerous);
    if (!approved) return ToolResult.err('User declined deletion.');
    await MemoryService.instance.delete(id);
    await onChange();
    return ToolResult.ok('Deleted memory $id.');
  }
}
