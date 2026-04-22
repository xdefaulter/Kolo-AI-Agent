import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/tools/tool_base.dart';
import '../../core/tools/tool_bootstrap.dart';
import '../../core/tools/tool_registry.dart';
import '../../core/permissions/permission_manager.dart';
import '../../core/storage/database.dart';
import '../../core/agent/agent_session.dart';

// Tool registry — shared with chat screen
final toolsScreenRegistryProvider = Provider<ToolRegistry>((ref) => bootstrapTools());

// Permission modes state
final toolPermissionModesProvider = StateNotifierProvider<ToolPermissionModesNotifier, Map<String, ToolPermissionMode>>((ref) {
  return ToolPermissionModesNotifier(ref);
});

class ToolPermissionModesNotifier extends StateNotifier<Map<String, ToolPermissionMode>> {
  final Ref _ref;
  ToolPermissionModesNotifier(this._ref) : super({}) {
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    final registry = _ref.read(toolsScreenRegistryProvider);
    final pm = PermissionManager();
    await pm.loadPersistedSettings();
    pm.initDefaults(registry.all);
    state = Map.from(pm.allModes);
  }

  void setMode(String toolName, ToolPermissionMode mode) {
    state = {...state, toolName: mode};
    _persistToDb();
  }

  void setAllToMode(ToolPermissionMode mode) {
    final registry = _ref.read(toolsScreenRegistryProvider);
    final newState = <String, ToolPermissionMode>{};
    for (final tool in registry.all) {
      newState[tool.name] = mode;
    }
    state = newState;
    _persistToDb();
  }

  void resetToDefaults() {
    final registry = _ref.read(toolsScreenRegistryProvider);
    final newState = <String, ToolPermissionMode>{};
    for (final tool in registry.all) {
      newState[tool.name] = _defaultMode(tool.permission);
    }
    state = newState;
    _persistToDb();
  }

  static ToolPermissionMode _defaultMode(ToolPermission perm) {
    switch (perm) {
      case ToolPermission.safe:
        return ToolPermissionMode.alwaysAllow;
      case ToolPermission.sensitive:
        return ToolPermissionMode.askEveryTime;
      case ToolPermission.dangerous:
        return ToolPermissionMode.askEveryTime;
    }
  }

  Future<void> _persistToDb() async {
    final modesStr = state.entries
        .map((e) => '${e.key}:${e.value.name}')
        .join(',');
    await AppDatabase.instance.saveSetting('tool_permission_modes', modesStr);

    // Also sync to the active permission manager
    final session = _ref.read(agentSessionProvider.notifier).session;
    if (session != null) {
      final pm = session.permissionManager;
      for (final entry in state.entries) {
        pm.setMode(entry.key, entry.value);
      }
    }
  }
}

class ToolsPermissionScreen extends ConsumerWidget {
  const ToolsPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(toolsScreenRegistryProvider);
    final modes = ref.watch(toolPermissionModesProvider);
    final tools = registry.all;

    // Group tools by permission level
    final safeTools = tools.where((t) => t.permission == ToolPermission.safe).toList();
    final sensitiveTools = tools.where((t) => t.permission == ToolPermission.sensitive).toList();
    final dangerousTools = tools.where((t) => t.permission == ToolPermission.dangerous).toList();

    final enabledCount = tools.where((t) => modes[t.name] != ToolPermissionMode.neverAllow).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Tools ($enabledCount/${tools.length})'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              final notifier = ref.read(toolPermissionModesProvider.notifier);
              switch (value) {
                case 'enable_all':
                  notifier.setAllToMode(ToolPermissionMode.alwaysAllow);
                  break;
                case 'disable_all':
                  notifier.setAllToMode(ToolPermissionMode.neverAllow);
                  break;
                case 'ask_all':
                  notifier.setAllToMode(ToolPermissionMode.askEveryTime);
                  break;
                case 'reset':
                  notifier.resetToDefaults();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'enable_all', child: Text('Enable All')),
              const PopupMenuItem(value: 'ask_all', child: Text('Ask for All')),
              const PopupMenuItem(value: 'disable_all', child: Text('Disable All')),
              const PopupMenuItem(value: 'reset', child: Text('Reset to Defaults')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(
            icon: Icons.check_circle_outline,
            title: 'Safe',
            subtitle: 'Auto-approved, no risk',
            color: Colors.green,
          ),
          ...safeTools.map((t) => _ToolTile(
            tool: t,
            mode: modes[t.name] ?? ToolPermissionMode.alwaysAllow,
            onChanged: (mode) => ref.read(toolPermissionModesProvider.notifier).setMode(t.name, mode),
          )),
          const SizedBox(height: 16),
          _SectionHeader(
            icon: Icons.warning_amber_outlined,
            title: 'Sensitive',
            subtitle: 'May access personal data or make changes',
            color: Colors.orange,
          ),
          ...sensitiveTools.map((t) => _ToolTile(
            tool: t,
            mode: modes[t.name] ?? ToolPermissionMode.askEveryTime,
            onChanged: (mode) => ref.read(toolPermissionModesProvider.notifier).setMode(t.name, mode),
          )),
          const SizedBox(height: 16),
          _SectionHeader(
            icon: Icons.dangerous_outlined,
            title: 'Dangerous',
            subtitle: 'Destructive or irreversible actions',
            color: Colors.red,
          ),
          ...dangerousTools.map((t) => _ToolTile(
            tool: t,
            mode: modes[t.name] ?? ToolPermissionMode.askEveryTime,
            onChanged: (mode) => ref.read(toolPermissionModesProvider.notifier).setMode(t.name, mode),
          )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final KoloTool tool;
  final ToolPermissionMode mode;
  final ValueChanged<ToolPermissionMode> onChanged;

  const _ToolTile({
    required this.tool,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      leading: Icon(
        _toolIcon(tool.name),
        size: 20,
        color: mode == ToolPermissionMode.neverAllow
            ? cs.onSurface.withValues(alpha: 0.3)
            : cs.primary,
      ),
      title: Text(
        tool.name,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          decoration: mode == ToolPermissionMode.neverAllow ? TextDecoration.lineThrough : null,
          color: mode == ToolPermissionMode.neverAllow ? cs.onSurface.withValues(alpha: 0.4) : null,
        ),
      ),
      subtitle: Text(
        tool.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
      ),
      trailing: _buildModeSelector(cs),
    );
  }

  Widget _buildModeSelector(ColorScheme cs) {
    // Three-state segmented toggle: ✓ Always | ? Ask | ✗ Never
    return SegmentedButton<ToolPermissionMode>(
      segments: const [
        ButtonSegment(value: ToolPermissionMode.alwaysAllow, icon: Icon(Icons.check, size: 16), tooltip: 'Always Allow'),
        ButtonSegment(value: ToolPermissionMode.askEveryTime, icon: Icon(Icons.help_outline, size: 16), tooltip: 'Ask Every Time'),
        ButtonSegment(value: ToolPermissionMode.neverAllow, icon: Icon(Icons.block, size: 16), tooltip: 'Never Allow'),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  IconData _toolIcon(String name) {
    return switch (name) {
      'read_file' || 'list_directory' || 'list_files' || 'file_stat' => Icons.description_outlined,
      'write_file' || 'append_file' => Icons.edit_outlined,
      'delete_file' => Icons.delete_outline,
      'copy_file' || 'move_file' => Icons.drive_file_move_outline,
      'create_directory' => Icons.create_new_folder_outlined,
      'calculator' => Icons.calculate_outlined,
      'web_search' => Icons.search,
      'clipboard_read' || 'clipboard_write' => Icons.content_paste,
      'shell_exec' => Icons.terminal,
      'http_get' || 'http_post' => Icons.cloud_outlined,
      'current_datetime' => Icons.access_time,
      'json_parse' => Icons.data_object,
      'base64' => Icons.code,
      'hash' => Icons.fingerprint,
      'grep' => Icons.find_in_page,
      'env_info' => Icons.info_outline,
      _ => Icons.build_outlined,
    };
  }
}