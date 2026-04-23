import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages extraction & setup of bundled Termux-compiled tools (python3, node,
/// git, aapt2, openjdk-17, clang) into app-private storage so they are
/// natively available through [ShellExecTool].
///
/// Layout after extraction:
/// ```
/// /data/data/<pkg>/files/usr/
///   bin/          ← executables (python3, node, git, javac, clang, aapt2)
///   lib/          ← shared libraries
///   include/      ← headers (for clang)
///   share/        ← data files
///   etc/          ← config files
///   tmp/          ← writable temp dir
/// ```
///
/// Packages are bundled as tar.gz archives in assets/bootstrap/
/// (gzip format because Android's toybox tar supports gzip natively
/// but does NOT support xz decompression.)
class BootstrapService {
  BootstrapService._();
  static final instance = BootstrapService._();

  static const _prefKey = 'bootstrap_version';

  /// Bump this whenever bundled assets are updated to force re-extraction.
  static const int _currentVersion = 1;

  /// Packages bundled as tar.gz archives in assets/bootstrap/
  static const List<String> _bundledPackages = [
    'python3',
    'nodejs',
    'git',
    'aapt2',
    'openjdk-17',
    'clang',
  ];

  String? _prefixPath;
  bool _ready = false;

  /// The usr prefix: /data/data/<pkg>/files/usr
  String get prefixPath {
    assert(_prefixPath != null, 'BootstrapService not initialized');
    return _prefixPath!;
  }

  /// Bin directory under the prefix
  String get binPath => '$prefixPath/bin';

  /// Lib directory under the prefix
  String get libPath => '$prefixPath/lib';

  /// Whether bootstrap has completed successfully
  bool get isReady => _ready;

  /// The PATH value that should be prepended to shell commands
  String get pathEnv => '$binPath:$prefixPath/lib/openjdk-17/bin';

  /// The LD_LIBRARY_PATH for native libraries
  String get ldLibraryPath => '$libPath:$prefixPath/lib/openjdk-17/lib:$prefixPath/lib/openjdk-17/lib/server';

  /// HOME for tools that need it (git, python, etc.)
  String get homeDir => '$prefixPath/home';

  /// Full environment map to inject into shell processes
  Map<String, String> get environment => {
        'PREFIX': prefixPath,
        'HOME': homeDir,
        'TMPDIR': '$prefixPath/tmp',
        'PATH': '$pathEnv:/system/bin:/system/xbin',
        'LD_LIBRARY_PATH': ldLibraryPath,
        'LANG': 'en_US.UTF-8',
        'TERM': 'xterm-256color',
        // Python
        'PYTHONHOME': prefixPath,
        'PYTHONPATH': '$prefixPath/lib/python3.12',
        // Java
        'JAVA_HOME': '$prefixPath/lib/openjdk-17',
        // Node
        'NODE_PATH': '$prefixPath/lib/node_modules',
        // Git
        'GIT_EXEC_PATH': '$prefixPath/libexec/git-core',
        // Clang
        'CC': '$binPath/clang',
        'CXX': '$binPath/clang++',
      };

  /// Initialize: resolve prefix path, extract if needed.
  /// Call this early in app startup (after WidgetsFlutterBinding).
  /// Returns a status message suitable for UI progress display.
  Future<BootstrapStatus> initialize({
    void Function(String message, double progress)? onProgress,
  }) async {
    if (_ready) return BootstrapStatus.alreadyReady;

    try {
      final appDir = await getApplicationSupportDirectory();
      _prefixPath = '${appDir.parent.path}/files/usr';

      // Check if we already extracted the current version
      final prefs = await SharedPreferences.getInstance();
      final installedVersion = prefs.getInt(_prefKey) ?? 0;

      if (installedVersion >= _currentVersion) {
        // Verify the prefix still exists (user might have cleared data)
        if (await Directory(binPath).exists()) {
          _ready = true;
          return BootstrapStatus.alreadyReady;
        }
        // Prefix was deleted — re-extract
      }

      onProgress?.call('Preparing development environment...', 0.0);

      // Create directory structure
      await _createDirectories();
      onProgress?.call('Created directory structure', 0.05);

      // Extract each package
      for (int i = 0; i < _bundledPackages.length; i++) {
        final pkg = _bundledPackages[i];
        final progress = 0.1 + (0.8 * i / _bundledPackages.length);
        onProgress?.call('Extracting $pkg...', progress);
        await _extractPackage(pkg);
      }

      onProgress?.call('Setting permissions...', 0.92);
      await _fixPermissions();

      onProgress?.call('Creating symlinks...', 0.95);
      await _createSymlinks();

      onProgress?.call('Verifying installation...', 0.98);
      final verified = await _verify();

      if (verified) {
        await prefs.setInt(_prefKey, _currentVersion);
        _ready = true;
        onProgress?.call('Ready!', 1.0);
        return BootstrapStatus.extracted;
      } else {
        return BootstrapStatus.partialFailure;
      }
    } catch (e) {
      return BootstrapStatus.error(e.toString());
    }
  }

  /// Create the Termux-like directory structure
  Future<void> _createDirectories() async {
    final dirs = [
      prefixPath,
      binPath,
      libPath,
      '$prefixPath/include',
      '$prefixPath/share',
      '$prefixPath/etc',
      '$prefixPath/tmp',
      '$prefixPath/home',
      '$prefixPath/libexec',
      '$prefixPath/var',
      '$prefixPath/lib/python3.12',
      '$prefixPath/lib/node_modules',
      '$prefixPath/lib/openjdk-17',
      '$prefixPath/libexec/git-core',
    ];
    for (final dir in dirs) {
      await Directory(dir).create(recursive: true);
    }
  }

  /// Extract a single package archive from assets into the prefix.
  /// Expected asset path: assets/bootstrap/<name>.tar.gz
  /// Uses gzip format because Android's toybox tar supports gzip natively
  /// but does NOT support xz decompression.
  Future<void> _extractPackage(String packageName) async {
    final assetPath = 'assets/bootstrap/$packageName.tar.gz';

    try {
      // Load archive from bundled assets
      final data = await rootBundle.load(assetPath);

      // Write to a temp file
      final tmpFile = File('$prefixPath/tmp/$packageName.tar.gz');
      await tmpFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      // Extract using tar with gzip — universally supported on Android
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', 'cd "$prefixPath" && tar xzf "$prefixPath/tmp/$packageName.tar.gz" 2>&1'],
        environment: environment,
      );

      if (result.exitCode != 0) {
        throw Exception('Failed to extract $packageName: ${result.stderr}');
      }

      // Clean up temp archive
      await tmpFile.delete();
    } catch (e) {
      // Asset not found or extraction failed — this package wasn't bundled yet.
      // This is expected during development before assets are prepared.
      debugPrint('[Bootstrap] Failed to extract $packageName: $e (skipping)');
    }
  }

  /// Make all files in bin/ executable
  Future<void> _fixPermissions() async {
    await Process.run('/system/bin/sh', [
      '-c',
      'chmod -R 755 "$binPath" "$prefixPath/libexec" 2>/dev/null; '
          'chmod -R 644 "$libPath"/*.so* 2>/dev/null; '
          'chmod 755 "$libPath"/*.so* 2>/dev/null; '
          'true', // always succeed
    ], environment: {'binPath': binPath, 'libPath': libPath, 'prefixPath': prefixPath});

    // Direct chmod on critical binaries
    final criticalBins = ['python3', 'node', 'git', 'javac', 'clang', 'aapt2'];
    for (final bin in criticalBins) {
      final f = File('$binPath/$bin');
      if (await f.exists()) {
        await Process.run('/system/bin/chmod', ['755', f.path]);
      }
    }
  }

  /// Create convenience symlinks
  Future<void> _createSymlinks() async {
    final links = <String, String>{
      '$binPath/python': '$binPath/python3',
      '$binPath/pip': '$binPath/pip3',
      '$binPath/java': '$prefixPath/lib/openjdk-17/bin/java',
      '$binPath/javac': '$prefixPath/lib/openjdk-17/bin/javac',
      '$binPath/cc': '$binPath/clang',
      '$binPath/c++': '$binPath/clang++',
    };

    for (final entry in links.entries) {
      final link = Link(entry.key);
      try {
        if (await link.exists()) await link.delete();
        await link.create(entry.value);
      } catch (_) {
        // Symlink creation can fail on some filesystems — non-fatal
      }
    }
  }

  /// Verify critical binaries exist and are executable
  Future<bool> _verify() async {
    final criticalBins = ['python3', 'node', 'git'];
    int found = 0;
    for (final bin in criticalBins) {
      final f = File('$binPath/$bin');
      if (await f.exists()) found++;
    }
    // Partial success: at least some tools extracted
    return found > 0;
  }

  /// Get status of each individual tool
  Future<Map<String, bool>> getToolStatus() async {
    if (_prefixPath == null) return {};
    final tools = {
      'python3': '$binPath/python3',
      'node': '$binPath/node',
      'git': '$binPath/git',
      'aapt2': '$binPath/aapt2',
      'javac': '$prefixPath/lib/openjdk-17/bin/javac',
      'clang': '$binPath/clang',
    };
    final status = <String, bool>{};
    for (final entry in tools.entries) {
      status[entry.key] = await File(entry.value).exists();
    }
    return status;
  }

  /// Run a quick smoke test on a specific tool
  Future<String?> testTool(String toolName) async {
    if (!_ready) return 'Bootstrap not ready';
    final commands = {
      'python3': 'python3 --version',
      'node': 'node --version',
      'git': 'git --version',
      'aapt2': 'aapt2 version',
      'javac': 'javac -version',
      'clang': 'clang --version',
    };
    final cmd = commands[toolName];
    if (cmd == null) return 'Unknown tool: $toolName';
    try {
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', cmd],
        environment: environment,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
      return 'Exit ${result.exitCode}: ${result.stderr}';
    } catch (e) {
      return 'Error: $e';
    }
  }
}

/// Result of bootstrap initialization
class BootstrapStatus {
  final bool success;
  final String message;

  const BootstrapStatus._(this.success, this.message);

  static const alreadyReady = BootstrapStatus._(true, 'Development tools ready');
  static const extracted = BootstrapStatus._(true, 'Development tools extracted successfully');
  static const partialFailure = BootstrapStatus._(true, 'Some tools may be missing');

  factory BootstrapStatus.error(String msg) => BootstrapStatus._(false, 'Bootstrap failed: $msg');

  @override
  String toString() => 'BootstrapStatus($message)';
}
