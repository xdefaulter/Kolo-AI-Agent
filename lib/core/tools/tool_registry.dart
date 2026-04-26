import 'tool_base.dart';

/// Registry of all available tools
class ToolRegistry {
  final Map<String, KoloTool> _tools = {};

  // Cached materialised views. The registry is mutated rarely (boot +
  // create_tool / delete_custom_tool). Reads happen on every send +
  // tool dispatch + settings render. Cache invalidation is just nulling
  // these on register/unregister.
  List<KoloTool>? _allCache;
  List<String>? _namesCache;
  final Map<ToolPlatform, List<KoloTool>> _platformCache = {};
  // Per-platform OpenAI function definitions WITHOUT the `isEnabled`
  // filter applied. Constructing `toFunctionDefinition()` walks the
  // tool's parameter schema map and builds a fresh Map every time —
  // that's the expensive part, not the filter. We cache the materialised
  // definitions paired with the tool and re-filter cheaply per call.
  final Map<ToolPlatform?, List<_DefinitionEntry>> _definitionsCache = {};

  void register(KoloTool tool) {
    _tools[tool.name] = tool;
    _invalidateCaches();
  }

  void unregister(String name) {
    if (_tools.remove(name) != null) {
      _invalidateCaches();
    }
  }

  void _invalidateCaches() {
    _allCache = null;
    _namesCache = null;
    _platformCache.clear();
    _definitionsCache.clear();
  }

  KoloTool? get(String name) => _tools[name];

  List<KoloTool> get all =>
      _allCache ??= List<KoloTool>.unmodifiable(_tools.values);

  /// Get tool names
  List<String> get names =>
      _namesCache ??= List<String>.unmodifiable(_tools.keys);

  /// Get all tools available for the current platform
  List<KoloTool> getForPlatform(ToolPlatform platform) {
    return _platformCache.putIfAbsent(
      platform,
      () => List<KoloTool>.unmodifiable(
        _tools.values.where(
          (t) => t.platform == ToolPlatform.all || t.platform == platform,
        ),
      ),
    );
  }

  /// Get OpenAI function definitions, optionally filtering to only enabled tools
  List<Map<String, dynamic>> getFunctionDefinitions({
    ToolPlatform? platform,
    bool Function(String toolName)? isEnabled,
  }) {
    final entries = _definitionsCache.putIfAbsent(platform, () {
      final tools =
          platform != null ? getForPlatform(platform) : _tools.values;
      return [
        for (final t in tools) _DefinitionEntry(t.name, t.toFunctionDefinition()),
      ];
    });
    if (isEnabled == null) {
      return [for (final e in entries) e.definition];
    }
    return [for (final e in entries) if (isEnabled(e.name)) e.definition];
  }

  bool contains(String name) => _tools.containsKey(name);
}

class _DefinitionEntry {
  final String name;
  final Map<String, dynamic> definition;
  const _DefinitionEntry(this.name, this.definition);
}