import 'dart:convert';
import '../tool_base.dart';
import '../../bootstrap/bootstrap_service.dart';

/// Lets the agent query which dev tools are installed and working.
class BootstrapStatusTool extends KoloTool {
  @override
  String get name => 'dev_tools_status';

  @override
  String get description =>
      'Check which bundled development tools (python3, node, git, javac, clang, aapt2) '
      'are installed and available in the shell environment.';

  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'test': {
            'type': 'string',
            'description':
                'Optional: name of a specific tool to smoke-test (python3, node, git, javac, clang, aapt2)',
          },
        },
        'required': [],
      };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> params, ToolContext context) async {
    final bootstrap = BootstrapService.instance;

    if (!bootstrap.isReady) {
      return ToolResult.ok(jsonEncode({
        'ready': false,
        'message':
            'Bootstrap not initialized yet. Dev tools may still be extracting.',
      }));
    }

    final testTool = params['test'] as String?;

    if (testTool != null) {
      final result = await bootstrap.testTool(testTool);
      return ToolResult.ok(jsonEncode({
        'ready': true,
        'tool': testTool,
        'result': result,
      }));
    }

    final status = await bootstrap.getToolStatus();
    return ToolResult.ok(jsonEncode({
      'ready': true,
      'prefix': bootstrap.prefixPath,
      'tools': status,
    }));
  }
}
