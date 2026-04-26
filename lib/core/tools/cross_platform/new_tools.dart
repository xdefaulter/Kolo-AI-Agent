import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import '../tool_base.dart';
import '../../bootstrap/bootstrap_service.dart';

/// Shared HttpClient for HttpGetTool/HttpPostTool so we don't pay a fresh
/// TCP+TLS handshake on every agent HTTP call.
final HttpClient _sharedHttpClient = HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..idleTimeout = const Duration(seconds: 30);

// ──────────────────────────────────────────────
// FILE & SYSTEM TOOLS
// ──────────────────────────────────────────────

class ListFilesTool extends KoloTool {
  @override
  String get name => 'list_files';
  @override
  String get description => 'List files and directories at a given path.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Directory path to list'},
      'recursive': {
        'type': 'boolean',
        'description': 'List recursively (default false)',
      },
    },
    'required': ['path'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final path = params['path'] as String;
    final recursive = params['recursive'] as bool? ?? false;
    try {
      final dir = Directory(path);
      if (!await dir.exists())
        return ToolResult.err('Directory not found: $path');
      // Stream-format straight into a StringBuffer instead of
      // materialising a List<FileSystemEntity> + a List<String> + a
      // joined String. For a recursive listing of a deep tree
      // (node_modules, build/, etc.) the previous version held two full
      // copies of every path in memory simultaneously — easily MBs of
      // pointer + string churn — before returning the joined output.
      final buf = StringBuffer();
      var first = true;
      await for (final entity in dir.list(recursive: recursive)) {
        if (!first) buf.write('\n');
        first = false;
        buf.write(entity is Directory ? 'DIR  ' : 'FILE ');
        buf.write(entity.path);
      }
      return ToolResult.ok(first ? '(empty)' : buf.toString());
    } catch (e) {
      return ToolResult.err('Failed to list: $e');
    }
  }
}

class DeleteFileTool extends KoloTool {
  @override
  String get name => 'delete_file';
  @override
  String get description =>
      'Delete a file at the given path. Only files within the workspace/project directories can be deleted.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Absolute path to file to delete (must be in workspace)',
      },
    },
    'required': ['path'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;

  /// Directories that are safe to delete files from
  static const _allowedPrefixes = [
    '/storage/emulated/0/Android/data/', // Android app-specific storage
    '/data/data/', // Android internal app data
    '/sdcard/KoloProjects/', // Kolo workspace
    '/tmp/', '/var/tmp/', // Temp dirs
  ];

  bool _isAllowedPath(String path) {
    final normalized = File(path).absolute.path;
    // Block dangerous system paths
    if (normalized.startsWith('/system') ||
        normalized.startsWith('/bin') ||
        normalized.startsWith('/sbin') ||
        normalized.startsWith('/etc') ||
        normalized.startsWith('/proc') ||
        normalized.startsWith('/dev')) {
      return false;
    }
    // Allow paths within known safe prefixes
    for (final prefix in _allowedPrefixes) {
      if (normalized.startsWith(prefix)) return true;
    }
    // Allow paths under Documents/KoloProjects (macOS/iOS)
    if (normalized.contains('/KoloProjects/') ||
        normalized.contains('/Documents/'))
      return true;
    // Allow paths under the temp directory
    if (normalized.startsWith(Directory.systemTemp.path)) return true;
    return false;
  }

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final path = params['path'] as String;
    if (!_isAllowedPath(path)) {
      return ToolResult.err(
        'Cannot delete files outside workspace directories. Path "$path" is not allowed.',
      );
    }
    try {
      final file = File(path);
      if (!await file.exists()) return ToolResult.err('File not found: $path');
      await file.delete();
      return ToolResult.ok('Deleted: $path');
    } catch (e) {
      return ToolResult.err('Failed to delete: $e');
    }
  }
}

class CreateDirectoryTool extends KoloTool {
  @override
  String get name => 'create_directory';
  @override
  String get description =>
      'Create a directory (and parents) at the given path.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Directory path to create'},
    },
    'required': ['path'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final path = params['path'] as String;
    try {
      await Directory(path).create(recursive: true);
      return ToolResult.ok('Created directory: $path');
    } catch (e) {
      return ToolResult.err('Failed to create directory: $e');
    }
  }
}

class AppendFileTool extends KoloTool {
  @override
  String get name => 'append_file';
  @override
  String get description =>
      'Append content to a file. Creates the file if it does not exist.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Absolute file path'},
      'content': {'type': 'string', 'description': 'Content to append'},
    },
    'required': ['path', 'content'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final path = params['path'] as String;
    final content = params['content'] as String;
    try {
      final file = File(path);
      await file.writeAsString(content, mode: FileMode.append, flush: true);
      return ToolResult.ok('Appended ${content.length} chars to $path');
    } catch (e) {
      return ToolResult.err('Failed to append: $e');
    }
  }
}

class CopyFileTool extends KoloTool {
  @override
  String get name => 'copy_file';
  @override
  String get description => 'Copy a file from source to destination.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'source': {'type': 'string', 'description': 'Source file path'},
      'destination': {'type': 'string', 'description': 'Destination file path'},
    },
    'required': ['source', 'destination'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final src = params['source'] as String;
    final dst = params['destination'] as String;
    try {
      await File(src).copy(dst);
      return ToolResult.ok('Copied $src → $dst');
    } catch (e) {
      return ToolResult.err('Failed to copy: $e');
    }
  }
}

class MoveFileTool extends KoloTool {
  @override
  String get name => 'move_file';
  @override
  String get description => 'Move/rename a file from source to destination.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'source': {'type': 'string', 'description': 'Source file path'},
      'destination': {'type': 'string', 'description': 'Destination file path'},
    },
    'required': ['source', 'destination'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final src = params['source'] as String;
    final dst = params['destination'] as String;
    try {
      await File(src).rename(dst);
      return ToolResult.ok('Moved $src → $dst');
    } catch (e) {
      return ToolResult.err('Failed to move: $e');
    }
  }
}

class FileStatTool extends KoloTool {
  @override
  String get name => 'file_stat';
  @override
  String get description => 'Get file metadata: size, modified time, type.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'File or directory path'},
    },
    'required': ['path'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final path = params['path'] as String;
    try {
      final stat = await FileStat.stat(path);
      return ToolResult.ok(
        jsonEncode({
          'path': path,
          'type': stat.type.toString(),
          'size': stat.size,
          'modified': stat.modified.toIso8601String(),
          'accessed': stat.accessed.toIso8601String(),
          'mode': stat.modeString(),
        }),
      );
    } catch (e) {
      return ToolResult.err('Failed to stat: $e');
    }
  }
}

// ──────────────────────────────────────────────
// SHELL & EXECUTION TOOLS
// ──────────────────────────────────────────────

class ShellExecTool extends KoloTool {
  @override
  String get name => 'shell_exec';
  @override
  String get description =>
      'Execute a shell command and return stdout/stderr. Not available on iOS. Only allowed commands: ls, cat, head, tail, grep, find, wc, sort, uniq, diff, echo, pwd, whoami, date, which, file, stat, du, df, mkdir, touch, cp, mv, rm, chmod, tar, zip, unzip, curl, wget, git, python, python3, node, npm, npx, dart, flutter, pip, pip3, java, javac, go, cargo, make, cmake, gcc, g++, rustc.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'command': {'type': 'string', 'description': 'Shell command to execute'},
      'timeout': {
        'type': 'integer',
        'description': 'Timeout in seconds (default 30)',
      },
      'workingDirectory': {
        'type': 'string',
        'description': 'Working directory for the command',
      },
    },
    'required': ['command'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android; // iOS sandbox blocks process spawning

  /// Allowlist of commands that can be executed
  static const _allowedCommands = <String>{
    'ls',
    'cat',
    'head',
    'tail',
    'grep',
    'find',
    'wc',
    'sort',
    'uniq',
    'diff',
    'echo',
    'pwd',
    'whoami',
    'date',
    'which',
    'file',
    'stat',
    'du',
    'df',
    'mkdir',
    'touch',
    'cp',
    'mv',
    'rm',
    'chmod',
    'tar',
    'zip',
    'unzip',
    'curl',
    'wget',
    'git',
    'python',
    'python3',
    'node',
    'npm',
    'npx',
    'dart',
    'flutter',
    'pip',
    'pip3',
    'java',
    'javac',
    'go',
    'cargo',
    'make',
    'cmake',
    'gcc',
    'g++',
    'rustc',
    'sed',
    'awk',
    'tr',
    'cut',
    'xargs',
    'tee',
    'env',
    'printenv',
    'uname',
    'id',
    'ps',
    'kill',
    'adb',
    'fastboot',
    'aapt2',
    'clang',
    'clang++',
    'cc',
    'c++',
    // From the Termux bootstrap zip — all ship as part of the base
    // install, no `apt install` needed.
    'bash',
    'sh',
    'dash',
    'ar',
    'xz',
    'bzip2',
    'apt',
    'apt-get',
    'dpkg',
  };

  /// Extract the base command from a shell command string.
  /// Manual scan — avoids the RegExp split + intermediate `List<String>`
  /// the previous version allocated. Fires once per pipe-segment per
  /// shell-exec call; the cost compounds when the model strings many
  /// shell tools together in a single turn.
  String? _extractBaseCommand(String command) {
    final s = command;
    final n = s.length;
    int i = 0;
    while (i < n) {
      // Skip whitespace.
      while (i < n) {
        final c = s.codeUnitAt(i);
        if (c != 32 && c != 9) break;
        i++;
      }
      if (i >= n) return null;
      // Find the end of this token.
      final tokenStart = i;
      while (i < n) {
        final c = s.codeUnitAt(i);
        if (c == 32 || c == 9) break;
        i++;
      }
      final tokenEnd = i;
      // Skip env-var assignments at the start (VAR=val).
      // Token starts with non-`-` and contains `=` → it's a leading
      // assignment; move on to the next token.
      bool isEnvVar = false;
      if (tokenStart < tokenEnd && s.codeUnitAt(tokenStart) != 0x2D /* '-' */) {
        for (int j = tokenStart; j < tokenEnd; j++) {
          if (s.codeUnitAt(j) == 0x3D /* '=' */) {
            isEnvVar = true;
            break;
          }
        }
      }
      if (isEnvVar) continue;
      // Strip path prefix: keep only the segment after the last '/'.
      int cmdStart = tokenStart;
      for (int j = tokenEnd - 1; j >= tokenStart; j--) {
        if (s.codeUnitAt(j) == 0x2F /* '/' */) {
          cmdStart = j + 1;
          break;
        }
      }
      return s.substring(cmdStart, tokenEnd);
    }
    return null;
  }

  /// Check for dangerous shell metacharacters that enable injection or
  /// out-of-band side effects.
  /// - `&` (backgrounding): `ls & rm -rf /` would run both; allowlist sees `ls`.
  /// - `>` / `<` (redirection): `cat /etc/passwd > /sdcard/leaked` exfiltrates data.
  /// - `` ` `` / `$()` / `<()` / `>()` command & process substitution.
  /// - `;`, `&&`, `||`, newlines — statement separators.
  /// Single `|` is allowed — pipe segments are individually allowlisted below.
  static final _dangerousPattern = RegExp(r'[`;<>&]|\$\(|\|\||[\n\r]');

  bool _hasDangerousMetachars(String command) {
    return _dangerousPattern.hasMatch(command);
  }

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    if (Platform.isIOS)
      return ToolResult.err(
        'Shell execution is not available on iOS due to sandbox restrictions.',
      );
    final command = params['command'] as String;
    final timeoutSec = params['timeout'] as int? ?? 30;
    final workDir = params['workingDirectory'] as String?;

    // Security: check for dangerous metacharacters
    if (_hasDangerousMetachars(command)) {
      return ToolResult.err(
        'Command contains disallowed shell metacharacters (backticks, \$()). Use simple commands instead.',
      );
    }

    // Security: validate the base command(s) — split on pipes
    final segments = command.split('|');
    for (final segment in segments) {
      final baseCmd = _extractBaseCommand(segment.trim());
      if (baseCmd == null || baseCmd.isEmpty) continue;
      if (!_allowedCommands.contains(baseCmd)) {
        return ToolResult.err(
          'Command "$baseCmd" is not in the allowed commands list. Allowed: ${_allowedCommands.take(20).join(', ')}...',
        );
      }
    }

    final shell = Platform.isAndroid ? '/system/bin/sh' : '/bin/sh';

    // Inject bootstrap environment (Termux-compiled tools) on Android
    Map<String, String>? env;
    if (Platform.isAndroid) {
      final bootstrap = BootstrapService.instance;
      if (bootstrap.isReady) {
        env = Map<String, String>.from(Platform.environment);
        env.addAll(bootstrap.environment);
      }
    }

    try {
      final result = await Process.run(
        shell,
        ['-c', command],
        workingDirectory: workDir,
        environment: env,
      ).timeout(Duration(seconds: timeoutSec));
      final output = StringBuffer();
      if (result.stdout.toString().isNotEmpty) output.writeln(result.stdout);
      if (result.stderr.toString().isNotEmpty)
        output.writeln('STDERR: ${result.stderr}');
      return ToolResult.ok(
        output.toString().trim().isEmpty
            ? '(no output, exit ${result.exitCode})'
            : output.toString().trim(),
        metadata: {'exitCode': result.exitCode},
      );
    } on TimeoutException {
      return ToolResult.err('Command timed out after ${timeoutSec}s');
    } catch (e) {
      return ToolResult.err('Failed to execute: $e');
    }
  }
}

// ──────────────────────────────────────────────
// WEB & NETWORK TOOLS
// ──────────────────────────────────────────────

/// SSRF protection: block requests to private/internal IP ranges
bool _isBlockedUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    // Block cloud metadata endpoints
    if (host == '169.254.169.254' || host == 'metadata.google.internal')
      return true;

    // Block localhost variants
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0.0.0.0')
      return true;

    // Block private IP ranges (10.x, 172.16-31.x, 192.168.x)
    final parts = host.split('.');
    if (parts.length == 4) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      if (a == 10) return true;
      if (a == 172 && b != null && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 169 && b == 254) return true; // link-local
    }

    // Block file:// and other non-http schemes
    if (uri.scheme != 'http' && uri.scheme != 'https') return true;

    return false;
  } catch (_) {
    return true; // Block unparseable URLs
  }
}

class HttpGetTool extends KoloTool {
  @override
  String get name => 'http_get';
  @override
  String get description =>
      'Make an HTTP GET request to a URL and return the response body.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL to request'},
      'headers': {
        'type': 'object',
        'description': 'Optional headers as key-value pairs',
      },
    },
    'required': ['url'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final url = params['url'] as String;
    if (_isBlockedUrl(url))
      return ToolResult.err(
        'URL blocked: requests to private/internal addresses are not allowed.',
      );
    final headers = params['headers'] as Map<String, dynamic>? ?? {};
    try {
      final req = await _sharedHttpClient.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v.toString()));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      return ToolResult.ok(body, metadata: {'statusCode': resp.statusCode});
    } catch (e) {
      return ToolResult.err('HTTP GET failed: $e');
    }
  }
}

class HttpPostTool extends KoloTool {
  @override
  String get name => 'http_post';
  @override
  String get description => 'Make an HTTP POST request with a JSON body.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL to post to'},
      'body': {'type': 'object', 'description': 'JSON body'},
      'headers': {'type': 'object', 'description': 'Optional headers'},
    },
    'required': ['url', 'body'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final url = params['url'] as String;
    if (_isBlockedUrl(url))
      return ToolResult.err(
        'URL blocked: requests to private/internal addresses are not allowed.',
      );
    final body = params['body'];
    final headers = params['headers'] as Map<String, dynamic>? ?? {};
    try {
      final req = await _sharedHttpClient.postUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v.toString()));
      if (!headers.containsKey('Content-Type')) {
        req.headers.set('Content-Type', 'application/json');
      }
      req.write(jsonEncode(body));
      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      return ToolResult.ok(respBody, metadata: {'statusCode': resp.statusCode});
    } catch (e) {
      return ToolResult.err('HTTP POST failed: $e');
    }
  }
}

// ──────────────────────────────────────────────
// UTILITY TOOLS
// ──────────────────────────────────────────────

class DateTool extends KoloTool {
  @override
  String get name => 'current_datetime';
  @override
  String get description => 'Get the current date, time, and timezone.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'format': {
        'type': 'string',
        'description': 'Optional format (iso, unix, readable)',
      },
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final now = DateTime.now();
    final format = params['format'] as String? ?? 'readable';
    switch (format) {
      case 'iso':
        return ToolResult.ok(now.toIso8601String());
      case 'unix':
        return ToolResult.ok(now.millisecondsSinceEpoch.toString());
      default:
        return ToolResult.ok('${now.toIso8601String()} (${now.timeZoneName})');
    }
  }
}

class JsonParseTool extends KoloTool {
  @override
  String get name => 'json_parse';
  @override
  String get description => 'Parse and format a JSON string. Validates syntax.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'json': {'type': 'string', 'description': 'JSON string to parse/format'},
    },
    'required': ['json'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    try {
      final decoded = jsonDecode(params['json'] as String);
      return ToolResult.ok(const JsonEncoder.withIndent('  ').convert(decoded));
    } catch (e) {
      return ToolResult.err('Invalid JSON: $e');
    }
  }
}

class Base64Tool extends KoloTool {
  @override
  String get name => 'base64';
  @override
  String get description => 'Encode or decode base64 strings.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'input': {'type': 'string', 'description': 'String to encode/decode'},
      'mode': {
        'type': 'string',
        'enum': ['encode', 'decode'],
        'description': 'encode or decode',
      },
    },
    'required': ['input', 'mode'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final input = params['input'] as String;
    final mode = params['mode'] as String;
    try {
      if (mode == 'encode') {
        return ToolResult.ok(base64Encode(utf8.encode(input)));
      } else {
        return ToolResult.ok(utf8.decode(base64Decode(input)));
      }
    } catch (e) {
      return ToolResult.err('Base64 $mode failed: $e');
    }
  }
}

class HashTool extends KoloTool {
  @override
  String get name => 'hash';
  @override
  String get description => 'Compute SHA-256 hash of a string or file.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'input': {
        'type': 'string',
        'description': 'Text to hash, or file path if isFile=true',
      },
      'isFile': {
        'type': 'boolean',
        'description': 'Hash a file instead of text',
      },
      'algorithm': {
        'type': 'string',
        'enum': ['sha256', 'sha1', 'md5'],
        'description': 'Hash algorithm (default sha256)',
      },
    },
    'required': ['input'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final input = params['input'] as String;
    final isFile = params['isFile'] as bool? ?? false;
    final algo = params['algorithm'] as String? ?? 'sha256';
    try {
      Digest digest;
      if (isFile) {
        final file = File(input);
        if (!await file.exists())
          return ToolResult.err('File not found: $input');
        final bytes = await file.readAsBytes();
        digest = _hashBytes(bytes, algo);
      } else {
        final bytes = utf8.encode(input);
        digest = _hashBytes(bytes, algo);
      }
      return ToolResult.ok('$algo:${digest.toString()}');
    } catch (e) {
      return ToolResult.err('Hash failed: $e');
    }
  }

  Digest _hashBytes(List<int> bytes, String algo) {
    switch (algo) {
      case 'sha1':
        return sha1.convert(bytes);
      case 'md5':
        return md5.convert(bytes);
      default:
        return sha256.convert(bytes);
    }
  }
}

class GrepTool extends KoloTool {
  @override
  String get name => 'grep';
  @override
  String get description =>
      'Search for a pattern in a file (line-by-line text search).';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'File to search'},
      'pattern': {'type': 'string', 'description': 'Text pattern to find'},
      'ignoreCase': {
        'type': 'boolean',
        'description': 'Case-insensitive search (default true)',
      },
    },
    'required': ['path', 'pattern'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  /// Maximum matches returned before truncating — prevents runaway output
  /// and keeps agent context usage bounded.
  static const _maxMatches = 500;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final path = params['path'] as String;
    final pattern = params['pattern'] as String;
    final ignoreCase = params['ignoreCase'] as bool? ?? true;
    try {
      final file = File(path);
      if (!await file.exists()) return ToolResult.err('File not found: $path');
      // Stream line-by-line rather than readAsLines() to avoid OOM on large files.
      final matches = <String>[];
      // Case-insensitive: compile a literal-text regex once. Previously
      // every line paid an O(n) `String.toLowerCase()` that allocated a
      // throwaway lowercased copy — on a 50k-line file that's 50k garbage
      // strings + the GC pressure to clean them. The regex is built from
      // an escaped literal (no metachar interpretation) and runs the
      // engine's native case-folding in place, no extra allocation per
      // line.
      final RegExp? caseInsensitiveRe = ignoreCase
          ? RegExp(RegExp.escape(pattern), caseSensitive: false)
          : null;
      int lineNum = 0;
      bool truncated = false;
      final stream = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final raw in stream) {
        lineNum++;
        final hit = caseInsensitiveRe != null
            ? caseInsensitiveRe.hasMatch(raw)
            : raw.contains(pattern);
        if (hit) {
          matches.add('$lineNum: $raw');
          if (matches.length >= _maxMatches) {
            truncated = true;
            break;
          }
        }
      }
      if (matches.isEmpty) return ToolResult.ok('No matches found');
      final out = matches.join('\n');
      return ToolResult.ok(
        truncated ? '$out\n\n[truncated at $_maxMatches matches]' : out,
      );
    } catch (e) {
      return ToolResult.err('Grep failed: $e');
    }
  }
}

class EnvInfoTool extends KoloTool {
  @override
  String get name => 'env_info';
  @override
  String get description => 'Get environment info: platform, paths, locale.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {},
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    return ToolResult.ok(
      jsonEncode({
        'platform': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
        'pathSeparator': Platform.pathSeparator,
        'numberOfProcessors': Platform.numberOfProcessors,
        'dartVersion': Platform.version,
        'executable': Platform.executable,
        'environment': Platform.environment.keys
            .take(20)
            .toList(), // only keys for safety
      }),
    );
  }
}
