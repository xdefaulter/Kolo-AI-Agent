import 'dart:convert';

import 'tool_base.dart';

/// Kinds of user/agent-defined tools supported by the runtime.
///
/// - [shell]: legacy persisted kind. New shell tools cannot be created and
///   legacy shell tools are not registered in the chat tool runtime.
/// - [prompt]: delegates to a sub-LLM call with a custom system prompt
///   and a user-message template. Works everywhere. No code execution.
/// - [composed]: expands into a sequence of existing tool calls with
///   shared template parameters. Safe, limited expressiveness.
enum CustomToolKind { shell, prompt, composed }

extension CustomToolKindX on CustomToolKind {
  String get wireName => switch (this) {
    CustomToolKind.shell => 'shell',
    CustomToolKind.prompt => 'prompt',
    CustomToolKind.composed => 'composed',
  };

  static CustomToolKind? parse(String? raw) {
    if (raw == null) return null;
    for (final v in CustomToolKind.values) {
      if (v.wireName == raw) return v;
    }
    return null;
  }
}

/// Persisted definition of a user- or agent-created tool. Lives in
/// [AppDatabase] as a JSON blob; materialised into a `CustomToolAdapter`
/// at registry build time.
class CustomToolDef {
  /// Internal, stable identifier. Separate from [name] so rename doesn't
  /// orphan permission settings or invalidate persisted references.
  final String id;

  /// Name the LLM sees (e.g. `resize_image`). Must be unique across
  /// built-ins + other custom tools.
  final String name;
  final String description;
  final Map<String, dynamic> parameterSchema;
  final ToolPermission permission;
  final CustomToolKind kind;

  /// Kind-specific config. For legacy [CustomToolKind.shell]:
  ///   `{ 'command': String, 'timeoutSec': int? }`
  /// For [CustomToolKind.prompt]:
  ///   `{ 'systemPrompt': String, 'userTemplate': String }`
  /// For [CustomToolKind.composed]:
  ///   `{ 'steps': [{ 'tool': String, 'args': Map }, …] }`
  final Map<String, dynamic> implementation;

  final DateTime createdAt;
  final DateTime updatedAt;

  CustomToolDef({
    required this.id,
    required this.name,
    required this.description,
    required this.parameterSchema,
    required this.permission,
    required this.kind,
    required this.implementation,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'parameterSchema': parameterSchema,
    'permission': permission.name,
    'kind': kind.wireName,
    'implementation': implementation,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CustomToolDef.fromMap(Map<String, dynamic> m) => CustomToolDef(
    id: m['id'] as String,
    name: m['name'] as String,
    description: m['description'] as String,
    parameterSchema: Map<String, dynamic>.from(m['parameterSchema'] as Map),
    permission: ToolPermission.values.firstWhere(
      (p) => p.name == m['permission'],
      orElse: () => ToolPermission.dangerous,
    ),
    kind: CustomToolKindX.parse(m['kind'] as String?) ?? CustomToolKind.shell,
    implementation: Map<String, dynamic>.from(m['implementation'] as Map),
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
  );

  /// A copy with updated fields — used when the agent edits an existing
  /// tool. [updatedAt] is refreshed automatically.
  CustomToolDef copyWith({
    String? name,
    String? description,
    Map<String, dynamic>? parameterSchema,
    ToolPermission? permission,
    CustomToolKind? kind,
    Map<String, dynamic>? implementation,
  }) => CustomToolDef(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    parameterSchema: parameterSchema ?? this.parameterSchema,
    permission: permission ?? this.permission,
    kind: kind ?? this.kind,
    implementation: implementation ?? this.implementation,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}

/// Safe-character set for template-rendered argument values. The template
/// STRUCTURE is author-trusted (the agent/user wrote it), but the VALUES
/// at runtime come from earlier tool output, user input, or LLM planning
/// and therefore aren't trusted.
///
/// Allow letters, digits, and a handful of commonly-needed separators.
/// Reject anything that could be a shell metacharacter.
final _templateValueSafe = RegExp(r'[^a-zA-Z0-9 ._\-/:=,@+%]');

/// Match either delimiter in one pass. Replaces a 2x `replaceAll` chain
/// that walked the value string twice — once for `{{` and once for `}}`.
final _templateDelim = RegExp(r'\{\{|\}\}');

/// Thrown when template rendering can't complete — typically because a
/// required placeholder has no matching argument.
class TemplateRenderError implements Exception {
  final String message;
  TemplateRenderError(this.message);
  @override
  String toString() => 'TemplateRenderError: $message';
}

/// Render a `{{name}}`-placeholder template with a map of args. Values
/// are stripped of shell metacharacters and wrapped in single quotes so
/// they're safe to paste into a shell command.
///
/// Non-string values are `jsonEncode`d first.
///
/// Throws [TemplateRenderError] if a placeholder has no corresponding
/// arg value.
String renderTemplate(String template, Map<String, dynamic> args) {
  // Cheap fast path: no placeholders means no work.
  if (!template.contains('{{')) return template;
  final out = StringBuffer();
  int i = 0;
  while (i < template.length) {
    final open = template.indexOf('{{', i);
    if (open < 0) {
      out.write(template.substring(i));
      break;
    }
    out.write(template.substring(i, open));
    final close = template.indexOf('}}', open + 2);
    if (close < 0) {
      // Unterminated placeholder — emit literally, don't throw.
      out.write(template.substring(open));
      break;
    }
    final key = template.substring(open + 2, close).trim();
    if (!args.containsKey(key)) {
      throw TemplateRenderError('missing arg: $key');
    }
    out.write(_quoteForShell(args[key]));
    i = close + 2;
  }
  return out.toString();
}

String _quoteForShell(dynamic value) {
  final asString = value is String ? value : jsonEncode(value);
  final cleaned = asString.replaceAll(_templateValueSafe, '');
  // Wrap in single quotes — literal in POSIX shells, no expansion.
  // Escape any stray single-quote by closing, inserting `\''`, reopening.
  final safe = cleaned.replaceAll("'", r"'\''");
  return "'$safe'";
}

/// Render `{{name}}` placeholders for *non-shell* contexts — specifically
/// the `prompt` and `composed` kinds where the rendered output goes to
/// another LLM or another tool's arg map rather than to a shell. The
/// value is inserted verbatim (no quoting, no shell-char stripping), but
/// template delimiters `{{` `}}` are still stripped from the value so a
/// malicious arg can't introduce a new placeholder.
///
/// Non-string values are JSON-encoded. Missing placeholders throw
/// [TemplateRenderError] to match [renderTemplate]'s contract.
String renderPlainTemplate(String template, Map<String, dynamic> args) {
  if (!template.contains('{{')) return template;
  final out = StringBuffer();
  int i = 0;
  while (i < template.length) {
    final open = template.indexOf('{{', i);
    if (open < 0) {
      out.write(template.substring(i));
      break;
    }
    out.write(template.substring(i, open));
    final close = template.indexOf('}}', open + 2);
    if (close < 0) {
      out.write(template.substring(open));
      break;
    }
    final key = template.substring(open + 2, close).trim();
    if (!args.containsKey(key)) {
      throw TemplateRenderError('missing arg: $key');
    }
    final value = args[key];
    final asString = value is String ? value : jsonEncode(value);
    // Strip our own template delimiters so a value like "{{other}}"
    // can't introduce a second-pass substitution. Single-pass regex —
    // walks the value once instead of twice.
    final stripped = asString.replaceAll(_templateDelim, '');
    out.write(stripped);
    i = close + 2;
  }
  return out.toString();
}
