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
enum ToolPlatform { all, android, ios }

/// Sub-LLM call shape used by the `prompt`-kind custom tool adapter.
/// `systemPrompt` and `userMessage` are passed through to whatever chat
/// completion API is wired up (respects the active provider's model).
/// Returns the assistant's text response (no tool calls — prompt tools
/// are pure text-in/text-out).
typedef ToolSubLlmCall =
    Future<String> Function({
      required String systemPrompt,
      required String userMessage,
    });

/// Execute another tool by name. Used by the `composed`-kind custom tool
/// adapter to chain existing capabilities. Permissions are checked by
/// the implementation; callers should not assume the call went through.
typedef ToolRunByName =
    Future<ToolResult> Function(String toolName, Map<String, dynamic> params);

/// Context provided to every tool execution.
///
/// The three callbacks below are the app's extensibility surface:
///   * [permissionChecker] — re-check permission for escalation paths
///   * [subLlmCall] — run a one-shot LLM call (prompt-kind custom tools)
///   * [runToolByName] — invoke another tool with its full permission
///     flow (composed-kind custom tools)
///
/// Both new callbacks are nullable because not every call site has them
/// wired — e.g., tests that construct a [ToolContext] manually. Tools
/// that need them should degrade gracefully when missing.
class ToolContext {
  final String chatId;
  final Future<bool> Function(ToolPermission) permissionChecker;

  /// Present when an active LLM provider is configured. Null during
  /// tests and early startup.
  final ToolSubLlmCall? subLlmCall;

  /// Present when invoked from the agent's main tool loop. Null when a
  /// tool is invoked outside the router (e.g., manual test harness).
  final ToolRunByName? runToolByName;

  ToolContext({
    required this.chatId,
    required this.permissionChecker,
    this.subLlmCall,
    this.runToolByName,
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
