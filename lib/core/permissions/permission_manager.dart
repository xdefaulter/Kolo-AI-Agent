import '../tools/tool_base.dart';
import '../storage/database.dart';

/// Permission mode for each tool
enum ToolPermissionMode {
  /// Always allow, no prompt
  alwaysAllow,
  /// Ask every time
  askEveryTime,
  /// Always deny
  neverAllow,
}

/// Manages tool execution permissions
class PermissionManager {
  final Map<String, ToolPermissionMode> _toolModes = {};
  bool autoApprove = false;

  // Callbacks set by UI layer
  Future<bool> Function(String toolName, Map<String, dynamic> params, ToolPermission permission)? promptUser;
  Future<bool> Function(String toolName, Map<String, dynamic> params, ToolPermission permission)? biometricPrompt;

  /// Get the permission mode for a tool
  ToolPermissionMode getMode(String toolName) {
    return _toolModes[toolName] ?? _defaultModeForPermission(
      // This is a fallback — callers should use the tool's actual permission
      ToolPermission.safe,
    );
  }

  /// Set the permission mode for a tool.
  /// [persist] controls whether to save to DB — false when called from
  /// ToolPermissionModesNotifier which handles its own persistence.
  void setMode(String toolName, ToolPermissionMode mode, {bool persist = true}) {
    _toolModes[toolName] = mode;
    if (persist) _persistSettings();
  }

  /// Check whether a tool is enabled (i.e., not neverAllow)
  bool isEnabled(String toolName) {
    return _toolModes[toolName] != ToolPermissionMode.neverAllow;
  }

  /// Get all tool modes
  Map<String, ToolPermissionMode> get allModes => Map.unmodifiable(_toolModes);

  static ToolPermissionMode _defaultModeForPermission(ToolPermission perm) {
    switch (perm) {
      case ToolPermission.safe:
        return ToolPermissionMode.alwaysAllow;
      case ToolPermission.sensitive:
        return ToolPermissionMode.askEveryTime;
      case ToolPermission.dangerous:
        return ToolPermissionMode.askEveryTime;
    }
  }

  /// Initialize default modes for all tools
  void initDefaults(List<KoloTool> tools) {
    for (final tool in tools) {
      _toolModes.putIfAbsent(tool.name, () => _defaultModeForPermission(tool.permission));
    }
    _persistSettings();
  }

  /// Load persisted permission settings from DB
  Future<void> loadPersistedSettings() async {
    final alwaysStr = await AppDatabase.instance.getSetting('always_allow_tools');
    final neverStr = await AppDatabase.instance.getSetting('never_allow_tools');
    final modesStr = await AppDatabase.instance.getSetting('tool_permission_modes');

    // Legacy support: old always/never strings
    if (alwaysStr != null && alwaysStr.isNotEmpty) {
      for (final name in alwaysStr.split(',')) {
        _toolModes[name] = ToolPermissionMode.alwaysAllow;
      }
    }
    if (neverStr != null && neverStr.isNotEmpty) {
      for (final name in neverStr.split(',')) {
        _toolModes[name] = ToolPermissionMode.neverAllow;
      }
    }

    // New format: mode per tool
    if (modesStr != null && modesStr.isNotEmpty) {
      // Format: "toolName:mode,toolName:mode,..."
      for (final entry in modesStr.split(',')) {
        final parts = entry.split(':');
        if (parts.length == 2) {
          final name = parts[0];
          final mode = ToolPermissionMode.values.firstWhere(
            (m) => m.name == parts[1],
            orElse: () => ToolPermissionMode.askEveryTime,
          );
          _toolModes[name] = mode;
        }
      }
    }
  }

  /// Persist current permission settings to DB (single write — modes format is authoritative)
  Future<void> _persistSettings() async {
    final modesStr = _toolModes.entries
        .map((e) => '${e.key}:${e.value.name}')
        .join(',');
    await AppDatabase.instance.saveSetting('tool_permission_modes', modesStr);
  }

  /// Legacy compatibility
  void alwaysAllow(String toolName) {
    _toolModes[toolName] = ToolPermissionMode.alwaysAllow;
    _persistSettings();
  }

  void neverAllow(String toolName) {
    _toolModes[toolName] = ToolPermissionMode.neverAllow;
    _persistSettings();
  }

  void removeAlwaysAllow(String toolName) {
    _toolModes.remove(toolName);
    _persistSettings();
  }

  void removeNeverAllow(String toolName) {
    _toolModes.remove(toolName);
    _persistSettings();
  }

  Future<bool> checkPermission(
    ToolPermission permission, {
    required String toolName,
    required Map<String, dynamic> params,
  }) async {
    final mode = _toolModes[toolName] ?? _defaultModeForPermission(permission);

    switch (mode) {
      case ToolPermissionMode.alwaysAllow:
        return true;
      case ToolPermissionMode.neverAllow:
        return false;
      case ToolPermissionMode.askEveryTime:
        if (permission == ToolPermission.dangerous && biometricPrompt != null) {
          return await biometricPrompt!(toolName, params, permission);
        }
        if (promptUser != null) {
          return await promptUser!(toolName, params, permission);
        }
        return permission != ToolPermission.dangerous;
    }
  }
}