import 'dart:io';
import '../tool_base.dart';

class ReadFileTool extends KoloTool {
  @override
  String get name => 'read_file';
  @override
  String get description =>
      'Read the contents of a file with line numbers. '
      'Supports offset and limit to read specific line ranges, '
      'avoiding reading entire large files.';
  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute path to the file',
          },
          'offset': {
            'type': 'integer',
            'description':
                'Start reading from this line number (1-indexed). Default: 1.',
          },
          'limit': {
            'type': 'integer',
            'description':
                'Maximum number of lines to return. Default: all lines.',
          },
        },
        'required': ['path'],
      };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> params, ToolContext context) async {
    final path = params['path'] as String;
    final offset = (params['offset'] as int?) ?? 1;
    final limit = params['limit'] as int?;

    if (offset < 1) {
      return ToolResult.err('offset must be >= 1');
    }

    try {
      final file = File(path);
      if (!await file.exists()) return ToolResult.err('File not found: $path');
      final allLines = await file.readAsLines();
      final totalLines = allLines.length;

      // Apply offset (1-indexed) and limit
      final startIdx = (offset - 1).clamp(0, totalLines);
      final endIdx =
          limit != null ? (startIdx + limit).clamp(0, totalLines) : totalLines;

      final buf = StringBuffer();
      for (int i = startIdx; i < endIdx; i++) {
        buf.writeln('${i + 1}\t${allLines[i]}');
      }

      final linesReturned = endIdx - startIdx;

      return ToolResult.ok(buf.toString().trimRight(), metadata: {
        'path': path,
        'total_lines': totalLines,
        'lines_returned': linesReturned,
        'offset': startIdx + 1,
        'category': 'file_read',
      });
    } catch (e) {
      return ToolResult.err('Failed to read file: $e');
    }
  }
}