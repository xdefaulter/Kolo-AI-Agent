import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../tool_base.dart';

/// Download a file from a URL to the device downloads directory.
class DownloadFileTool extends KoloTool {
  @override
  String get name => 'download_file';
  @override
  String get description => 'Download a file from a URL and save it to the device. Returns the local file path.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL of the file to download'},
      'filename': {'type': 'string', 'description': 'Filename to save as (auto-detected from URL if omitted)'},
      'directory': {'type': 'string', 'enum': ['downloads', 'documents', 'temp'], 'description': 'Where to save (default downloads)'},
    },
    'required': ['url'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final url = params['url'] as String;
    final filename = params['filename'] as String?;
    final dirType = params['directory'] as String? ?? 'downloads';

    try {
      // Determine save directory
      final Directory saveDir;
      switch (dirType) {
        case 'documents':
          saveDir = await getApplicationDocumentsDirectory();
        case 'temp':
          saveDir = await getTemporaryDirectory();
        default:
          saveDir = await getApplicationDocumentsDirectory();
      }

      // Determine filename
      String saveName = filename ?? _filenameFromUrl(url);
      final filePath = '${saveDir.path}/$saveName';

      // Download the file
      final dio = Dio();
      await dio.download(
        url,
        filePath,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final file = File(filePath);
      final size = await file.length();

      return ToolResult.ok('Downloaded: $filePath (${_formatSize(size)})', metadata: {
        'path': filePath,
        'size': size,
        'url': url,
      });
    } catch (e) {
      return ToolResult.err('Download failed: $e');
    }
  }

  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final lastSegment = path.split('/').last;
      if (lastSegment.isNotEmpty && lastSegment.contains('.')) return lastSegment;
    } catch (_) {}
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Search for files by name pattern across storage.
class FindFileTool extends KoloTool {
  @override
  String get name => 'find_file';
  @override
  String get description => 'Search for files by name pattern (glob) in a directory tree. Returns matching file paths.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'pattern': {'type': 'string', 'description': 'Filename pattern to search for (e.g. "*.txt", "photo*.jpg")'},
      'directory': {'type': 'string', 'description': 'Directory to search in (default: app documents)'},
      'max_results': {'type': 'integer', 'description': 'Maximum results to return (default 20)'},
      'recursive': {'type': 'boolean', 'description': 'Search recursively (default true)'},
    },
    'required': ['pattern'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final pattern = params['pattern'] as String;
    final dir = params['directory'] as String?;
    final maxResults = params['max_results'] as int? ?? 20;
    final recursive = params['recursive'] as bool? ?? true;

    try {
      final Directory searchDir;
      if (dir != null && dir.isNotEmpty) {
        searchDir = Directory(dir);
      } else {
        searchDir = await getApplicationDocumentsDirectory();
      }

      if (!await searchDir.exists()) {
        return ToolResult.err('Directory not found: ${searchDir.path}');
      }

      final regex = RegExp(_globToRegex(pattern), caseSensitive: false);
      final results = <String>[];

      await for (final entity in searchDir.list(recursive: recursive)) {
        if (results.length >= maxResults) break;
        final name = entity.path.split('/').last.split('\\').last;
        if (regex.hasMatch(name)) {
          final type = entity is Directory ? 'DIR' : 'FILE';
          try {
            final stat = await entity.stat();
            results.add('$type ${entity.path} (${_formatSize(stat.size)})');
          } catch (_) {
            results.add('$type ${entity.path}');
          }
        }
      }

      if (results.isEmpty) {
        return ToolResult.ok('No files matching "$pattern" found in ${searchDir.path}');
      }
      return ToolResult.ok('Found ${results.length} file(s) matching "$pattern":\n${results.join('\n')}');
    } catch (e) {
      return ToolResult.err('Search failed: $e');
    }
  }

  String _globToRegex(String glob) {
    return glob
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}