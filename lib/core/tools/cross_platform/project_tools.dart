import 'dart:io';
import '../tool_base.dart';

/// Session-scoped project root that other tools can reference
class ProjectRoot {
  static String? root;

  /// Resolve a path: if absolute, return as-is. If relative and project root is set, resolve against it.
  static String resolve(String path) {
    if (path.startsWith('/')) return path;
    if (root != null) {
      return '${root!}${Platform.pathSeparator}$path';
    }
    return path;
  }
}

class SetProjectRootTool extends KoloTool {
  @override
  String get name => 'set_projectroot';
  @override
  String get description =>
      'Set the project root directory for the current session. '
      'After setting, file tools can use relative paths. '
      'Call with no arguments to clear, or with path to set.';
  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the project root. Omit to clear.',
          },
        },
        'required': [],
      };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> params, ToolContext context) async {
    final path = params['path'] as String?;

    if (path == null || path.isEmpty) {
      ProjectRoot.root = null;
      return ToolResult.ok('Project root cleared.');
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      return ToolResult.err('Directory not found: $path');
    }

    ProjectRoot.root = path;
    return ToolResult.ok('Project root set to: $path', metadata: {
      'projectroot': path,
    });
  }
}
