import 'dart:io';
import '../tool_base.dart';

class WriteFileTool extends KoloTool {
  @override String get name => 'write_file';
  @override String get description => 'Write content to a file. Creates parent dirs if needed.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Absolute path'},
      'content': {'type': 'string', 'description': 'Content to write'},
      'append': {'type': 'boolean', 'description': 'Append instead of overwrite', 'default': false},
    },
    'required': ['path', 'content'],
  };
  @override ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final path = params['path'] as String;
    final content = params['content'] as String;
    final append = (params['append'] as bool?) ?? false;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, mode: append ? FileMode.append : FileMode.write);
      final size = await file.length();
      return ToolResult.ok(append ? 'Appended to $path' : 'Wrote $size bytes to $path', metadata: {'path': path, 'size': size});
    } catch (e) {
      return ToolResult.err('Failed to write file: $e');
    }
  }
}