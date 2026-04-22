import 'dart:io';
import '../tool_base.dart';

class ReadFileTool extends KoloTool {
  @override
  String get name => 'read_file';
  @override
  String get description => 'Read the contents of a file from the device.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Absolute path to the file'},
    },
    'required': ['path'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final path = params['path'] as String;
    try {
      final file = File(path);
      if (!await file.exists()) return ToolResult.err('File not found: $path');
      final content = await file.readAsString();
      return ToolResult.ok(content, metadata: {'path': path, 'size': content.length});
    } catch (e) {
      return ToolResult.err('Failed to read file: $e');
    }
  }
}