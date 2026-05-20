import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/tools/tool_base.dart';
import '../../core/permissions/permission_manager.dart';
import '../../core/storage/database.dart';
import '../../core/agent/agent_session.dart';

// 3.5: Reuse the shared tool registry instead of creating a separate one.
import '../chat/chat_screen.dart' show toolRegistryProvider;

final toolsScreenRegistryProvider = toolRegistryProvider;

// Permission modes state
final toolPermissionModesProvider =
    StateNotifierProvider<
      ToolPermissionModesNotifier,
      Map<String, ToolPermissionMode>
    >((ref) {
      return ToolPermissionModesNotifier(ref);
    });

class ToolPermissionModesNotifier
    extends StateNotifier<Map<String, ToolPermissionMode>> {
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

    // Sync to the active permission manager (persist: false — we already saved)
    final session = _ref.read(agentSessionProvider.notifier).session;
    if (session != null) {
      final pm = session.permissionManager;
      for (final entry in state.entries) {
        pm.setMode(entry.key, entry.value, persist: false);
      }
    }
  }
}

class ToolsPermissionScreen extends ConsumerStatefulWidget {
  const ToolsPermissionScreen({super.key});

  @override
  ConsumerState<ToolsPermissionScreen> createState() =>
      _ToolsPermissionScreenState();
}

class _ToolsPermissionScreenState extends ConsumerState<ToolsPermissionScreen> {
  final _searchController = TextEditingController();

  /// Lowercase cache so we don't `.toLowerCase()` per-keystroke on every tool.
  /// 50+ tools × every keystroke adds up; caching drops it to a single pass
  /// per search change.
  List<_IndexedTool>? _index;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(toolsScreenRegistryProvider);
    final modes = ref.watch(toolPermissionModesProvider);
    final tools = registry.all;

    // Rebuild lowercase-cached index only when the tool list changes.
    if (_index == null || _index!.length != tools.length) {
      _index = [
        for (final t in tools)
          _IndexedTool(
            tool: t,
            nameLower: t.name.toLowerCase(),
            descLower: t.description.toLowerCase(),
          ),
      ];
    }

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _index!
        : [
            for (final idx in _index!)
              if (idx.nameLower.contains(q) || idx.descLower.contains(q)) idx,
          ];

    final safe = <_IndexedTool>[];
    final sensitive = <_IndexedTool>[];
    final dangerous = <_IndexedTool>[];
    for (final idx in filtered) {
      switch (idx.tool.permission) {
        case ToolPermission.safe:
          safe.add(idx);
        case ToolPermission.sensitive:
          sensitive.add(idx);
        case ToolPermission.dangerous:
          dangerous.add(idx);
      }
    }

    final enabledCount = tools
        .where((t) => modes[t.name] != ToolPermissionMode.neverAllow)
        .length;

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
              const PopupMenuItem(
                value: 'enable_all',
                child: Text('Enable All'),
              ),
              const PopupMenuItem(value: 'ask_all', child: Text('Ask for All')),
              const PopupMenuItem(
                value: 'disable_all',
                child: Text('Disable All'),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Text('Reset to Defaults'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search tools…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 40,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No tools match "$_query"',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      if (safe.isNotEmpty) ...[
                        const _SectionHeader(
                          icon: Icons.check_circle_outline,
                          title: 'Safe',
                          subtitle: 'Auto-approved, no risk',
                          color: Colors.green,
                        ),
                        ...safe.map(
                          (t) => _ToolTile(
                            tool: t.tool,
                            mode:
                                modes[t.tool.name] ??
                                ToolPermissionMode.alwaysAllow,
                            onChanged: (m) => ref
                                .read(toolPermissionModesProvider.notifier)
                                .setMode(t.tool.name, m),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (sensitive.isNotEmpty) ...[
                        const _SectionHeader(
                          icon: Icons.warning_amber_outlined,
                          title: 'Sensitive',
                          subtitle: 'May access personal data or make changes',
                          color: Colors.orange,
                        ),
                        ...sensitive.map(
                          (t) => _ToolTile(
                            tool: t.tool,
                            mode:
                                modes[t.tool.name] ??
                                ToolPermissionMode.askEveryTime,
                            onChanged: (m) => ref
                                .read(toolPermissionModesProvider.notifier)
                                .setMode(t.tool.name, m),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (dangerous.isNotEmpty) ...[
                        const _SectionHeader(
                          icon: Icons.dangerous_outlined,
                          title: 'Dangerous',
                          subtitle: 'Destructive or irreversible actions',
                          color: Colors.red,
                        ),
                        ...dangerous.map(
                          (t) => _ToolTile(
                            tool: t.tool,
                            mode:
                                modes[t.tool.name] ??
                                ToolPermissionMode.askEveryTime,
                            onChanged: (m) => ref
                                .read(toolPermissionModesProvider.notifier)
                                .setMode(t.tool.name, m),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pre-lowercased tool index entry. Built once, reused across filter
/// keystrokes so we don't pay `.toLowerCase()` on every char typed.
class _IndexedTool {
  final KoloTool tool;
  final String nameLower;
  final String descLower;
  const _IndexedTool({
    required this.tool,
    required this.nameLower,
    required this.descLower,
  });
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
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
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
          decoration: mode == ToolPermissionMode.neverAllow
              ? TextDecoration.lineThrough
              : null,
          color: mode == ToolPermissionMode.neverAllow
              ? cs.onSurface.withValues(alpha: 0.4)
              : null,
        ),
      ),
      subtitle: Text(
        tool.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurface.withValues(alpha: 0.5),
        ),
      ),
      trailing: _buildModeSelector(cs),
    );
  }

  Widget _buildModeSelector(ColorScheme cs) {
    // Three-state segmented toggle: ✓ Always | ? Ask | ✗ Never
    return SegmentedButton<ToolPermissionMode>(
      segments: const [
        ButtonSegment(
          value: ToolPermissionMode.alwaysAllow,
          icon: Icon(Icons.check, size: 16),
          tooltip: 'Always Allow',
        ),
        ButtonSegment(
          value: ToolPermissionMode.askEveryTime,
          icon: Icon(Icons.help_outline, size: 16),
          tooltip: 'Ask Every Time',
        ),
        ButtonSegment(
          value: ToolPermissionMode.neverAllow,
          icon: Icon(Icons.block, size: 16),
          tooltip: 'Never Allow',
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  IconData _toolIcon(String name) {
    return switch (name) {
      'calculator' => Icons.calculate_outlined,
      'web_search' => Icons.search,
      'list_skills' || 'read_skill' || 'create_skill' => Icons.auto_stories,
      'clipboard_read' || 'clipboard_write' => Icons.content_paste,
      'http_get' || 'http_post' => Icons.cloud_outlined,
      'current_datetime' => Icons.access_time,
      'json_parse' => Icons.data_object,
      'base64' => Icons.transform,
      'hash' => Icons.fingerprint,
      _ => Icons.build_outlined,
    };
  }
}
