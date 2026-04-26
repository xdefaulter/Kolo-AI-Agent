import 'dart:io';
import '../tool_base.dart';

class SearchFilesTool extends KoloTool {
  @override
  String get name => 'search_files';
  @override
  String get description =>
      'Search for a regex pattern across files in a directory tree. '
      'Useful for finding class definitions, usages, imports, or any text pattern across a codebase.';
  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'Regex pattern to search for',
          },
          'path': {
            'type': 'string',
            'description':
                'Root directory to search in (absolute path). Defaults to current directory.',
          },
          'file_glob': {
            'type': 'string',
            'description':
                'File name filter, e.g. "*.dart", "*.ts". Matches file name only, not path.',
          },
          'output_mode': {
            'type': 'string',
            'enum': ['files_only', 'content', 'count'],
            'description':
                'files_only: list matching file paths. content: show matching lines with context. count: show match count per file. Default: content.',
          },
          'context': {
            'type': 'integer',
            'description': 'Number of context lines before and after each match (default 0). Only used with content mode.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of matching lines to return (default 100). Prevents overwhelming output.',
          },
        },
        'required': ['pattern'],
      };
  @override
  ToolPermission get permission => ToolPermission.safe;

  static const int _defaultMaxResults = 100;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> params, ToolContext context) async {
    final pattern = params['pattern'] as String;
    final rootPath = params['path'] as String? ?? Directory.current.path;
    final fileGlob = params['file_glob'] as String?;
    final outputMode = params['output_mode'] as String? ?? 'content';
    final ctxLines = params['context'] as int? ?? 0;
    final maxResults = params['max_results'] as int? ?? _defaultMaxResults;

    RegExp regex;
    try {
      regex = RegExp(pattern);
    } catch (e) {
      return ToolResult.err('Invalid regex pattern: $e');
    }

    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      return ToolResult.err('Directory not found: $rootPath');
    }

    // Collect matching files
    final results = StringBuffer();
    int totalMatches = 0;
    int filesMatched = 0;
    bool truncated = false;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (_shouldSkip(entity.path)) continue;
      if (fileGlob != null && !_matchGlob(entity.path, fileGlob)) continue;

      List<String> lines;
      try {
        lines = await entity.readAsLines();
      } catch (_) {
        continue; // skip binary/unreadable files
      }

      final matchingLines = <int>[];
      for (int i = 0; i < lines.length; i++) {
        if (regex.hasMatch(lines[i])) {
          matchingLines.add(i);
        }
      }

      if (matchingLines.isEmpty) continue;
      filesMatched++;

      switch (outputMode) {
        case 'files_only':
          results.writeln(entity.path);
          break;
        case 'count':
          results.writeln('${entity.path}: ${matchingLines.length}');
          break;
        case 'content':
        default:
          results.writeln('── ${entity.path} ──');
          final shownLineIndices = <int>{};
          for (final lineIdx in matchingLines) {
            if (totalMatches >= maxResults) {
              truncated = true;
              break;
            }
            final start = (lineIdx - ctxLines).clamp(0, lines.length);
            final end = (lineIdx + ctxLines + 1).clamp(0, lines.length);
            for (int k = start; k < end; k++) {
              if (shownLineIndices.add(k)) {
                final prefix = k == lineIdx ? '>' : ' ';
                results.writeln('$prefix${k + 1}: ${lines[k]}');
              }
            }
            totalMatches++;
          }
          results.writeln();
          break;
      }

      if (truncated) break;
      totalMatches += outputMode != 'content' ? matchingLines.length : 0;
    }

    if (filesMatched == 0) {
      return ToolResult.ok('No matches found for pattern: $pattern',
          metadata: {'category': 'search', 'matches': 0});
    }

    final summary = truncated
        ? '[Truncated at $maxResults matches. Use max_results to increase.]\n'
        : '';
    return ToolResult.ok('$summary${results.toString().trimRight()}',
        metadata: {
          'category': 'search',
          'files_matched': filesMatched,
          'total_matches': totalMatches,
        });
  }

  bool _shouldSkip(String path) {
    // Walk segments without materialising the split list. For a recursive
    // search this runs once per file in the tree, so avoiding the
    // intermediate List allocation matters. We also fold the binary-ext
    // check into the same single pass so we touch each char at most twice.
    final sep = Platform.pathSeparator.codeUnitAt(0);
    final dot = '.'.codeUnitAt(0);
    int segStart = 0;
    for (int i = 0; i <= path.length; i++) {
      final atEnd = i == path.length;
      if (atEnd || path.codeUnitAt(i) == sep) {
        final len = i - segStart;
        if (len > 0) {
          // Skip dotted dirs/files (`.git`, `.dart_tool`, etc.) — but
          // not the literal `.` self-segment.
          if (path.codeUnitAt(segStart) == dot && len > 1) return true;
          if (len == 12 && path.startsWith('node_modules', segStart)) {
            return true;
          }
          if (len == 5 && path.startsWith('build', segStart)) return true;
          // `.dart_tool` and `.gradle` are already caught by the
          // dotted-segment rule above.
        }
        segStart = i + 1;
      }
    }
    // Binary extension check — find last '.' from end without splitting.
    final lastDot = path.lastIndexOf('.');
    if (lastDot < 0 || lastDot == path.length - 1) return false;
    final ext = path.substring(lastDot + 1).toLowerCase();
    return _binaryExts.contains(ext);
  }

  static const _binaryExts = {
    'png', 'jpg', 'jpeg', 'gif', 'ico', 'webp', 'bmp',
    'zip', 'tar', 'gz', 'jar', 'so', 'dylib', 'exe',
    'pdf', 'ttf', 'otf', 'woff', 'woff2',
  };

  bool _matchGlob(String filePath, String glob) {
    // Find the last separator without allocating a split list.
    final sepIdx = filePath.lastIndexOf(Platform.pathSeparator);
    final fileName =
        sepIdx >= 0 ? filePath.substring(sepIdx + 1) : filePath;
    // Simple glob: *.ext or exact name
    if (glob.startsWith('*.')) {
      return fileName.endsWith(glob.substring(1));
    }
    return fileName == glob;
  }
}
