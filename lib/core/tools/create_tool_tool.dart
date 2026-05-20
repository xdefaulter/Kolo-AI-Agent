import 'package:uuid/uuid.dart';

import '../storage/database.dart';
import 'custom_tool_def.dart';
import 'tool_base.dart';

const _uuid = Uuid();

/// Meta-tool: lets the agent define new custom tools at runtime. Only
/// registered when the user has enabled "Custom Tools" in Settings
/// ([kAgentCanCreateToolsSettingKey] below).
///
/// The agent provides a [CustomToolDef] shape; we validate + save +
/// bump [customToolsVersionProvider] so the registry picks it up. The
/// new tool lands in the agent's tool list on its next turn.
///
/// Permission: `dangerous`. Every creation attempt prompts the user with
/// the name + description of the tool so they can refuse if the agent
/// tries to define something suspicious.
class CreateToolTool extends KoloTool {
  /// Called after the def is persisted so the registry can reload.
  /// Injected rather than held directly as a Ref to decouple the tool
  /// from Riverpod's lifecycle (tool instances may outlive a provider
  /// rebuild and a stale Ref would be a bug).
  final Future<void> Function() onChange;

  CreateToolTool({required this.onChange});

  @override
  String get name => 'create_tool';

  @override
  String get description =>
      'Define a new custom tool for yourself. The tool persists across chats '
      'and becomes available on your next turn. USE THIS SPARINGLY — every '
      'creation requires the user to approve. Prefer the built-in tools '
      'when they already do what you need. Prompt tools run a focused LLM '
      'call; composed tools chain existing tools with {{param_name}} '
      'placeholders.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'name': {
        'type': 'string',
        'description':
            'Tool name (snake_case). Must not collide with a built-in.',
      },
      'description': {
        'type': 'string',
        'description':
            'What the tool does. Future-you will read this when deciding to call the tool.',
      },
      'parameterSchema': {
        'type': 'object',
        'description':
            'JSON Schema describing the tool\'s parameters, same shape '
            'as existing tool schemas. Must have type=object + properties.',
      },
      'kind': {
        'type': 'string',
        'enum': ['prompt', 'composed'],
        'description':
            'Implementation kind. Shell/code execution tools are not supported.',
      },
      'implementation': {
        'type': 'object',
        'description':
            'Kind-specific. For prompt: {"systemPrompt": "...", "userTemplate": "..."}. '
            'For composed: {"steps": [{"tool":"...","args":{...}}]}.',
      },
      'permission': {
        'type': 'string',
        'enum': ['safe', 'sensitive', 'dangerous'],
        'description':
            'Default permission level. Optional — defaults to "dangerous" '
            'so the user is prompted on first use.',
      },
    },
    'required': [
      'name',
      'description',
      'parameterSchema',
      'kind',
      'implementation',
    ],
  };

  @override
  ToolPermission get permission => ToolPermission.dangerous;

  /// Names reserved for built-in tools. We check against the *live* registry
  /// rather than a hardcoded list so this stays correct as tools are added.
  static final _reservedMetaTools = {
    'create_tool',
    'list_custom_tools',
    'delete_custom_tool',
  };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final name = (params['name'] as String?)?.trim() ?? '';
    final description = (params['description'] as String?)?.trim() ?? '';
    final parameterSchema = params['parameterSchema'];
    final kindRaw = params['kind'] as String?;
    final implementation = params['implementation'];
    final permissionRaw = params['permission'] as String?;

    // ── Validation ─────────────────────────────────────────────────
    if (name.isEmpty || !RegExp(r'^[a-z][a-z0-9_]{1,39}$').hasMatch(name)) {
      return ToolResult.err(
        'name must be snake_case, start with a letter, and be 2-40 chars.',
      );
    }
    if (_reservedMetaTools.contains(name)) {
      return ToolResult.err('"$name" is reserved for built-in meta-tools.');
    }
    if (description.length < 10) {
      return ToolResult.err(
        'description must be at least 10 characters — future-you needs context.',
      );
    }
    if (parameterSchema is! Map) {
      return ToolResult.err('parameterSchema must be an object.');
    }
    if (parameterSchema['type'] != 'object' ||
        parameterSchema['properties'] is! Map) {
      return ToolResult.err(
        'parameterSchema must be {"type":"object","properties":{…}}',
      );
    }
    final kind = CustomToolKindX.parse(kindRaw);
    if (kind == null) {
      return ToolResult.err('kind must be "prompt" or "composed".');
    }
    if (kind == CustomToolKind.shell) {
      return ToolResult.err('Shell/code execution custom tools are disabled.');
    }
    if (implementation is! Map) {
      return ToolResult.err('implementation must be an object.');
    }
    final implMap = Map<String, dynamic>.from(implementation);
    final implErr = _validateImplementation(kind, implMap);
    if (implErr != null) return ToolResult.err(implErr);

    final permission = switch (permissionRaw) {
      'safe' => ToolPermission.safe,
      'sensitive' => ToolPermission.sensitive,
      _ => ToolPermission.dangerous,
    };

    // ── Name collision with another tool (built-in or custom) ─────
    final existing = await AppDatabase.instance.getAllCustomTools();
    final duplicate = existing.firstWhere(
      (t) => t.name == name,
      orElse: () => _sentinel,
    );
    final isOverwrite = !identical(duplicate, _sentinel);

    // ── Save ───────────────────────────────────────────────────────
    final def = CustomToolDef(
      id: isOverwrite ? duplicate.id : _uuid.v4(),
      name: name,
      description: description,
      parameterSchema: Map<String, dynamic>.from(parameterSchema),
      permission: permission,
      kind: kind,
      implementation: implMap,
    );

    try {
      await AppDatabase.instance.saveCustomTool(def);
    } on StateError catch (e) {
      return ToolResult.err(e.message);
    }

    // Trigger registry reload so the new tool shows up on the agent's
    // next turn. Caller provides the callback when constructing the tool.
    await onChange();

    return ToolResult.ok(
      'Custom tool "$name" ${isOverwrite ? "updated" : "created"}. '
      'It will be available on your next turn. Permission: ${permission.name}.',
      metadata: {
        'toolId': def.id,
        'overwrite': isOverwrite,
        'permission': permission.name,
      },
    );
  }

  /// Per-kind validation of the `implementation` map.
  String? _validateImplementation(
    CustomToolKind kind,
    Map<String, dynamic> impl,
  ) {
    switch (kind) {
      case CustomToolKind.shell:
        return 'Shell/code execution custom tools are disabled.';
      case CustomToolKind.prompt:
        final sys = impl['systemPrompt'];
        final usr = impl['userTemplate'];
        if (sys is! String || sys.isEmpty) {
          return 'prompt kind requires implementation.systemPrompt.';
        }
        if (usr is! String || usr.isEmpty) {
          return 'prompt kind requires implementation.userTemplate.';
        }
        return null;
      case CustomToolKind.composed:
        final steps = impl['steps'];
        if (steps is! List || steps.isEmpty) {
          return 'composed kind requires implementation.steps (non-empty array).';
        }
        for (int i = 0; i < steps.length; i++) {
          final step = steps[i];
          if (step is! Map || step['tool'] is! String || step['args'] is! Map) {
            return 'Step $i must be {"tool":"string","args":{...}}.';
          }
        }
        return null;
    }
  }

  // Single sentinel instance used with firstWhere(orElse:) to detect absence.
  static final CustomToolDef _sentinel = CustomToolDef(
    id: '_sentinel',
    name: '_sentinel',
    description: '_',
    parameterSchema: const {'type': 'object', 'properties': {}},
    permission: ToolPermission.safe,
    kind: CustomToolKind.prompt,
    implementation: const {'systemPrompt': '_', 'userTemplate': '_'},
  );
}

/// Sibling meta-tool: lists the agent's currently-saved custom tools.
/// Cheap + read-only + always registered alongside [CreateToolTool]; the
/// agent can check what it has defined before deciding whether to create
/// a new one or reuse an existing one.
class ListCustomToolsTool extends KoloTool {
  ListCustomToolsTool();

  @override
  String get name => 'list_custom_tools';

  @override
  String get description =>
      'List all custom tools the agent has previously defined (id, name, '
      'description, kind, permission). Use this to avoid creating duplicates.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'type': 'object',
    'properties': {},
    'required': [],
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final tools = await AppDatabase.instance.getAllCustomTools();
    final callable = tools
        .where((t) => t.kind != CustomToolKind.shell)
        .toList();
    if (callable.isEmpty) {
      if (tools.any((t) => t.kind == CustomToolKind.shell)) {
        return ToolResult.ok(
          '(no callable custom tools defined; legacy shell tools are disabled)',
          metadata: {'count': 0, 'disabledLegacyCount': tools.length},
        );
      }
      return ToolResult.ok('(no custom tools defined)');
    }
    final lines = callable.map(
      (t) =>
          '- ${t.name} (${t.kind.wireName}, ${t.permission.name}): ${t.description}',
    );
    return ToolResult.ok(
      lines.join('\n'),
      metadata: {
        'count': callable.length,
        'disabledLegacyCount': tools.length - callable.length,
      },
    );
  }
}

/// Sibling meta-tool: deletes a custom tool by name. Paired with
/// [CreateToolTool] so the agent can clean up after itself.
class DeleteCustomToolTool extends KoloTool {
  final Future<void> Function() onChange;
  DeleteCustomToolTool({required this.onChange});

  @override
  String get name => 'delete_custom_tool';

  @override
  String get description =>
      'Delete a custom tool by name. Use list_custom_tools first to confirm '
      'the exact name. Requires user approval.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
    },
    'required': ['name'],
  };

  @override
  ToolPermission get permission => ToolPermission.dangerous;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final target = (params['name'] as String?)?.trim();
    if (target == null || target.isEmpty) {
      return ToolResult.err('name is required.');
    }
    final tools = await AppDatabase.instance.getAllCustomTools();
    final match = tools.where((t) => t.name == target).toList();
    if (match.isEmpty) {
      return ToolResult.err('No custom tool named "$target".');
    }
    await AppDatabase.instance.deleteCustomTool(match.first.id);
    await onChange();
    return ToolResult.ok('Deleted custom tool "$target".');
  }
}

/// Setting key for the "agent can create tools" toggle (persists in
/// AppDatabase settings, read by tool_bootstrap).
const String kAgentCanCreateToolsSettingKey = 'agent_can_create_tools';

/// Setting key for the "skills" toggle — enables skills manifest
/// injection and the create_skill helper.
const String kSkillsEnabledSettingKey = 'skills_enabled';

/// Default values (used when the setting hasn't been written yet).
const bool kDefaultAgentCanCreateTools = false;
const bool kDefaultSkillsEnabled = true;
