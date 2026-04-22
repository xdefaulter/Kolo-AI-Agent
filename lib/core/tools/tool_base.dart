/// Permission level for a tool
enum ToolPermission {
  /// Auto-approved, no risk
  safe,
  /// Needs user confirmation
  sensitive,
  /// Needs biometric + explicit approval
  dangerous,
}

/// Platform availability for a tool
enum ToolPlatform {
  all,
  android,
  ios,
}

/// Context provided to every tool execution
class ToolContext {
  final String chatId;
  final Future<bool> Function(ToolPermission) permissionChecker;

  ToolContext({
    required this.chatId,
    required this.permissionChecker,
  });
}

/// Result of a tool execution
class ToolResult {
  final bool success;
  final String output;
  final String? error;
  final Map<String, dynamic>? metadata;

  ToolResult({
    required this.success,
    required this.output,
    this.error,
    this.metadata,
  });

  factory ToolResult.ok(String output, {Map<String, dynamic>? metadata}) =>
      ToolResult(success: true, output: output, metadata: metadata);

  factory ToolResult.err(String error) =>
      ToolResult(success: false, output: '', error: error);

  /// Convert to the format expected by OpenAI tool result
  Map<String, dynamic> toApiFormat() => {
        'success': success,
        if (success) 'output': output,
        if (!success) 'error': error,
        if (metadata != null) ...metadata!,
      };

  String toDisplayString() {
    if (success) return output;
    return 'Error: $error';
  }
}

/// Base class for all Kolo tools
abstract class KoloTool {
  /// Unique identifier for this tool (e.g., "web_search")
  String get name;
  
  /// Human-readable description
  String get description;
  
  /// JSON Schema for parameters (OpenAI function calling format)
  Map<String, dynamic> get parameterSchema;
  
  /// Permission level required
  ToolPermission get permission;
  
  /// Platform availability
  ToolPlatform get platform => ToolPlatform.all;

  /// Execute the tool with given parameters
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context);

  /// Convert to OpenAI function definition format
  Map<String, dynamic> toFunctionDefinition() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameterSchema,
        },
      };
}