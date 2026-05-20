import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'tool_base.dart';

/// Skills live under `<app documents>/KoloProjects/skills/<name>/SKILL.md`.
///
/// A skill is a named multi-step workflow with instructions for the
/// agent. Unlike custom tools, skills don't add a new execution
/// primitive — they're filesystem documents the agent reads and
/// follows using its existing tools. Which makes them:
///   * Safe by construction (no new code paths)
///   * Cross-platform (just read files)
///   * Portable (can be shared by copying the folder)

/// Metadata parsed from a skill's `SKILL.md` frontmatter.
class SkillSummary {
  final String name;
  final String description;
  final String path; // path to the SKILL.md file
  final String? whenToUse;

  const SkillSummary({
    required this.name,
    required this.description,
    required this.path,
    this.whenToUse,
  });
}

/// Resolve the skills directory root: `<docs>/KoloProjects/skills/`.
/// Created lazily when first asked about.
Future<Directory> getSkillsDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/KoloProjects/skills');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Scan the skills directory and return summaries of every SKILL.md
/// found. Errors are swallowed — a malformed skill is skipped, not
/// fatal.
Future<List<SkillSummary>> listAvailableSkills() async {
  try {
    final dir = await getSkillsDirectory();
    // Parallelize per-skill file reads. The previous loop awaited
    // file.exists() then file.readAsString() sequentially per
    // directory, so N skills meant 2N serial disk hops; with 10+
    // skills that adds up at every system-prompt rebuild.
    final readJobs = <Future<SkillSummary?>>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! Directory) continue;
      final file = File('${e.path}/SKILL.md');
      readJobs.add(_readSkill(file));
    }
    final results = await Future.wait(readJobs);
    final summaries = <SkillSummary>[];
    for (final s in results) {
      if (s != null) summaries.add(s);
    }
    summaries.sort((a, b) => a.name.compareTo(b.name));
    return summaries;
  } catch (_) {
    return const [];
  }
}

Future<SkillSummary?> _readSkill(File file) async {
  try {
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return _parseSkillFrontmatter(content, file.path);
  } catch (_) {
    return null;
  }
}

/// Minimal YAML-frontmatter parser — we only need `name`, `description`,
/// optional `when_to_use`. Anything more structured is left to the
/// agent to read with `read_skill`. Returns null when the file has no
/// frontmatter or is missing the required fields.
SkillSummary? _parseSkillFrontmatter(String content, String path) {
  if (!content.startsWith('---')) return null;
  final end = content.indexOf('\n---', 3);
  if (end < 0) return null;
  final header = content.substring(3, end);
  final fields = <String, String>{};
  for (final line in header.split('\n')) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final key = line.substring(0, colon).trim();
    var value = line.substring(colon + 1).trim();
    // Strip surrounding single or double quotes
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    fields[key] = value;
  }
  final name = fields['name'];
  final description = fields['description'];
  if (name == null || name.isEmpty || description == null) return null;
  return SkillSummary(
    name: name,
    description: description,
    path: path,
    whenToUse: fields['when_to_use'],
  );
}

/// Build the manifest string injected into the system prompt. Empty
/// when no skills exist — the caller should just skip injection.
String buildSkillsManifest(List<SkillSummary> skills) {
  if (skills.isEmpty) return '';
  final buf = StringBuffer()
    ..writeln('## Available skills')
    ..writeln(
      'These are pre-authored workflows stored as SKILL.md files. To use one, '
      'call `read_skill` with its name, then follow the instructions using your '
      'existing tools. Do NOT try to invoke a skill directly — read it first.',
    )
    ..writeln();
  for (final s in skills) {
    buf.writeln('- **${s.name}**: ${s.description}');
    if (s.whenToUse != null && s.whenToUse!.isNotEmpty) {
      buf.writeln('  _when to use:_ ${s.whenToUse}');
    }
  }
  return buf.toString();
}

/// Tool: list skills. Read-only, `safe` permission.
class ListSkillsTool extends KoloTool {
  @override
  String get name => 'list_skills';

  @override
  String get description =>
      'List all available skills (pre-authored workflows). Each entry has a '
      'name and description. Use read_skill to load the full instructions for '
      'full instructions.';

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
    final skills = await listAvailableSkills();
    if (skills.isEmpty) return ToolResult.ok('(no skills defined)');
    final lines = skills.map((s) => '- ${s.name}: ${s.description}');
    return ToolResult.ok(lines.join('\n'), metadata: {'count': skills.length});
  }
}

/// Tool: read one saved skill by name. Narrower than a general file reader:
/// it only returns SKILL.md files from the app-managed skills directory.
class ReadSkillTool extends KoloTool {
  @override
  String get name => 'read_skill';

  @override
  String get description =>
      'Read the full SKILL.md instructions for one available skill by name.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'description': 'Skill name from list_skills'},
    },
    'required': ['name'],
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final name = (params['name'] as String?)?.trim() ?? '';
    if (!RegExp(r'^[a-z][a-z0-9_-]{1,39}$').hasMatch(name)) {
      return ToolResult.err(
        'name must be snake_case or kebab-case, 2-40 chars.',
      );
    }
    try {
      final skillsDir = await getSkillsDirectory();
      final file = File('${skillsDir.path}/$name/SKILL.md');
      if (!await file.exists()) {
        return ToolResult.err('Skill "$name" was not found.');
      }
      final content = await file.readAsString();
      return ToolResult.ok(content, metadata: {'path': file.path});
    } catch (e) {
      return ToolResult.err('Failed to read skill: $e');
    }
  }
}

/// Tool: author a new skill. Writes only inside the app-managed skills
/// directory and enforces the SKILL.md frontmatter format so authored
/// skills are discoverable by [listAvailableSkills].
class CreateSkillTool extends KoloTool {
  @override
  String get name => 'create_skill';

  @override
  String get description =>
      'Author a new skill as skills/<name>/SKILL.md. Skills are instruction '
      'playbooks you can call back to later — prefer this over '
      'create_tool when the workflow is a sequence of steps rather than a '
      'new capability.';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'type': 'object',
    'properties': {
      'name': {
        'type': 'string',
        'description': 'Skill name (snake_case, unique).',
      },
      'description': {
        'type': 'string',
        'description': 'One-line summary — shown in the manifest.',
      },
      'when_to_use': {
        'type': 'string',
        'description': 'Optional cue describing the trigger.',
      },
      'body': {
        'type': 'string',
        'description':
            'Markdown body of SKILL.md: steps, examples, edge cases.',
      },
    },
    'required': ['name', 'description', 'body'],
  };

  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final name = (params['name'] as String?)?.trim() ?? '';
    final description = (params['description'] as String?)?.trim() ?? '';
    final body = params['body'] as String? ?? '';
    final whenToUse = (params['when_to_use'] as String?)?.trim();

    if (!RegExp(r'^[a-z][a-z0-9_-]{1,39}$').hasMatch(name)) {
      return ToolResult.err(
        'name must be snake_case or kebab-case, 2-40 chars.',
      );
    }
    if (description.length < 10) {
      return ToolResult.err(
        'description must be at least 10 chars — it\'s what you\'ll read later.',
      );
    }
    if (body.isEmpty) return ToolResult.err('body is required.');

    try {
      final skillsDir = await getSkillsDirectory();
      final skillDir = Directory('${skillsDir.path}/$name');
      if (!await skillDir.exists()) await skillDir.create(recursive: true);
      final file = File('${skillDir.path}/SKILL.md');

      final header = StringBuffer()
        ..writeln('---')
        ..writeln('name: $name')
        ..writeln('description: ${_yamlEscape(description)}');
      if (whenToUse != null && whenToUse.isNotEmpty) {
        header.writeln('when_to_use: ${_yamlEscape(whenToUse)}');
      }
      header.writeln('---');
      header.writeln();
      header.write(body);

      await file.writeAsString(header.toString(), flush: true);
      return ToolResult.ok(
        'Skill "$name" written to ${file.path}. It\'ll appear in your skills '
        'manifest on the next session.',
        metadata: {'path': file.path},
      );
    } catch (e) {
      return ToolResult.err('Failed to write skill: $e');
    }
  }
}

/// Quote a value for YAML single-line scalar — only needed for chars
/// that would otherwise ambiguate the parser.
String _yamlEscape(String v) {
  if (v.contains(':') || v.contains('#') || v.trimLeft() != v) {
    return '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
  return v;
}
