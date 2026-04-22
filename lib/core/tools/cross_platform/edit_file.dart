import 'dart:io';
import '../tool_base.dart';

class EditFileTool extends KoloTool {
  @override
  String get name => 'edit_file';
  @override
  String get description =>
      'Edit a file by finding and replacing a specific string. '
      'Much more efficient than rewriting the entire file. '
      'Returns a unified diff of the change.';
  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Absolute path to the file to edit',
          },
          'old_string': {
            'type': 'string',
            'description':
                'The exact string to find in the file. Must match exactly (including whitespace and indentation).',
          },
          'new_string': {
            'type': 'string',
            'description':
                'The replacement string. Use empty string to delete the old_string.',
          },
          'replace_all': {
            'type': 'boolean',
            'description':
                'If true, replace ALL occurrences. If false (default), the old_string must appear exactly once or the edit fails.',
          },
        },
        'required': ['path', 'old_string', 'new_string'],
      };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> params, ToolContext context) async {
    final path = params['path'] as String;
    final oldString = params['old_string'] as String;
    final newString = params['new_string'] as String;
    final replaceAll = (params['replace_all'] as bool?) ?? false;

    if (oldString == newString) {
      return ToolResult.err('old_string and new_string are identical.');
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        return ToolResult.err('File not found: $path');
      }

      final content = await file.readAsString();

      // Count occurrences
      int count = 0;
      int searchFrom = 0;
      while (true) {
        final idx = content.indexOf(oldString, searchFrom);
        if (idx == -1) break;
        count++;
        searchFrom = idx + oldString.length;
      }

      if (count == 0) {
        return ToolResult.err(
            'old_string not found in $path. Make sure it matches exactly (including whitespace).');
      }

      if (!replaceAll && count > 1) {
        return ToolResult.err(
            'old_string found $count times in $path. Use replace_all=true to replace all, or provide a more specific old_string.');
      }

      // Perform replacement
      final newContent = replaceAll
          ? content.replaceAll(oldString, newString)
          : content.replaceFirst(oldString, newString);

      await file.writeAsString(newContent);

      // Build a concise diff output
      final diff = _buildDiff(content, newContent, path);
      final replacements = replaceAll ? count : 1;

      return ToolResult.ok(diff, metadata: {
        'path': path,
        'replacements': replacements,
        'category': 'file_edit',
      });
    } catch (e) {
      return ToolResult.err('Failed to edit file: $e');
    }
  }

  String _buildDiff(String oldContent, String newContent, String path) {
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');

    final buf = StringBuffer();
    buf.writeln('--- a/$path');
    buf.writeln('+++ b/$path');

    // Find changed regions
    int i = 0, j = 0;
    while (i < oldLines.length || j < newLines.length) {
      if (i < oldLines.length &&
          j < newLines.length &&
          oldLines[i] == newLines[j]) {
        i++;
        j++;
        continue;
      }

      // Found a difference — show context
      final ctxStart = (i - 2).clamp(0, oldLines.length);
      // Find end of changed region
      int oi = i, nj = j;
      while (oi < oldLines.length || nj < newLines.length) {
        if (oi < oldLines.length &&
            nj < newLines.length &&
            oldLines[oi] == newLines[nj]) {
          // Check if we have 3 consecutive matching lines (end of hunk)
          int match = 0;
          while (oi + match < oldLines.length &&
              nj + match < newLines.length &&
              oldLines[oi + match] == newLines[nj + match] &&
              match < 3) {
            match++;
          }
          if (match >= 3) break;
          oi++;
          nj++;
        } else if (oi < oldLines.length) {
          oi++;
        } else {
          nj++;
        }
      }

      final ctxEnd = (oi + 2).clamp(0, oldLines.length);
      final newCtxEnd = (nj + 2).clamp(0, newLines.length);

      buf.writeln(
          '@@ -${ctxStart + 1},${ctxEnd - ctxStart} +${(j - (i - ctxStart)) + 1},${newCtxEnd - (j - (i - ctxStart))} @@');

      // Context before
      for (int k = ctxStart; k < i; k++) {
        buf.writeln(' ${oldLines[k]}');
      }
      // Removed lines
      for (int k = i; k < oi; k++) {
        buf.writeln('-${oldLines[k]}');
      }
      // Added lines
      for (int k = j; k < nj; k++) {
        buf.writeln('+${newLines[k]}');
      }
      // Context after
      for (int k = oi; k < ctxEnd && k < oldLines.length; k++) {
        buf.writeln(' ${oldLines[k]}');
      }

      i = ctxEnd;
      j = newCtxEnd;
    }

    final result = buf.toString().trim();
    if (result.split('\n').length <= 2) {
      // No diff lines generated, just confirm
      return 'Edit applied to $path';
    }
    return result;
  }
}
