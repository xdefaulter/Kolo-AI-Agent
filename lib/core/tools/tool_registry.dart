import 'tool_base.dart';

/// Registry of all available tools
class ToolRegistry {
  final Map<String, KoloTool> _tools = {};

  void register(KoloTool tool) {
    _tools[tool.name] = tool;
  }

  void unregister(String name) {
    _tools.remove(name);
  }

  KoloTool? get(String name) => _tools[name];

  List<KoloTool> get all => _tools.values.toList();

  /// Get tool names
  List<String> get names => _tools.keys.toList();

  /// Get all tools available for the current platform
  List<KoloTool> getForPlatform(ToolPlatform platform) {
    return _tools.values
        .where((t) => t.platform == ToolPlatform.all || t.platform == platform)
        .toList();
  }

  /// Get OpenAI function definitions, optionally filtering to only enabled tools
  List<Map<String, dynamic>> getFunctionDefinitions({
    ToolPlatform? platform,
    bool Function(String toolName)? isEnabled,
  }) {
    var tools = platform != null ? getForPlatform(platform) : all;
    if (isEnabled != null) {
      tools = tools.where((t) => isEnabled(t.name)).toList();
    }
    return tools.map((t) => t.toFunctionDefinition()).toList();
  }

  bool contains(String name) => _tools.containsKey(name);
}