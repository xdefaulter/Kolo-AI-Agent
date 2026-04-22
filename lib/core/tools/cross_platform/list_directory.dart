import 'dart:io';
import '../tool_base.dart';

class ListDirectoryTool extends KoloTool {
  @override String get name => 'list_directory';
  @override String get description => 'List files and directories at a given path.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Directory path'},
      'recursive': {'type': 'boolean', 'description': 'List recursively', 'default': false},
    },
    'required': ['path'],
  };
  @override ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final path = params['path'] as String;
    final recursive = (params['recursive'] as bool?) ?? false;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return ToolResult.err('Directory not found: $path');
      final lines = <String>[];
      await for (final entity in dir.list(recursive: recursive)) {
        final name = entity.path.split('/').last;
        final isDir = entity is Directory;
        lines.add('${isDir ? "📁" : "📄"} $name');
      }
      return ToolResult.ok(lines.isEmpty ? 'Empty directory' : lines.join('\n'), metadata: {'count': lines.length});
    } catch (e) {
      return ToolResult.err('Failed to list: $e');
    }
  }
}