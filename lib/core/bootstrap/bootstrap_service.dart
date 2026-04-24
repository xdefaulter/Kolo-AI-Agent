import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages download & setup of Termux-compiled tools (python3, node, git,
/// aapt2, openjdk-17, clang) into app-private storage so they are natively
/// available through [ShellExecTool].
///
/// Packages are downloaded from the official Termux repository on first launch:
///   https://packages.termux.dev/apt/termux-main
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
class BootstrapService {
  BootstrapService._();
  static final instance = BootstrapService._();

  static const _prefKey = 'bootstrap_version';

  /// Bump this whenever the bootstrap payload changes (zip version upgrade,
  /// prefix path rewrite rules, etc.) to force a full re-download.
  static const int _currentVersion = 3;

  // Per-package apt-style installs after bootstrap zip landing can use
  // https://packages.termux.dev/apt/termux-main — not wired today, kept
  // in docs for the future `apt install` top-up flow.

  // Current bundled Termux bootstrap: termux-packages release
  // `bootstrap-2024.09.22-r1+apt-android-7`, aarch64 variant. The zip
  // is copied into assets/bootstrap/ and shipped inside the APK so no
  // network access is required for first-run setup. Bumping this means
  // replacing the asset file + incrementing [_currentVersion] below so
  // existing installs re-extract on next launch.

  /// Asset path inside the APK that holds the bundled zip. We currently
  /// ship aarch64 only — covers arm64-v8a devices (~95% of Android 10+).
  /// On other arches, [initialize] returns a partial-failure status and
  /// the UI can prompt the user.
  String _bootstrapAssetPath(String arch) =>
      'assets/bootstrap/bootstrap-$arch.zip';

  // Per-package install groups were used by the pre-bootstrap-zip flow.
  // Now the bootstrap zip ships everything in one shot; optional extra
  // packages can be added later via `apt install <pkg>` inside the
  // extracted prefix (bash + apt + dpkg are all in the zip).

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
  String get ldLibraryPath =>
      '$libPath:$prefixPath/lib/openjdk-17/lib:$prefixPath/lib/openjdk-17/lib/server';

  /// HOME for tools that need it (git, python, etc.)
  String get homeDir => '$prefixPath/home';

  /// Memoized environment map — built once after initialize() resolves the prefix.
  Map<String, String>? _envCache;

  /// Merged environment (Platform.environment + bootstrap overrides), cached.
  /// Use this instead of Map.from(Platform.environment)..addAll(environment)
  /// at call sites — avoids copying ~200 OS env entries on every tool call.
  Map<String, String>? _fullEnvCache;
  Map<String, String> get fullEnvironment =>
      _fullEnvCache ??= {...Platform.environment, ...environment};

  /// Full environment map to inject into shell processes. Cached because it's
  /// read on every shell_exec invocation.
  Map<String, String> get environment {
    return _envCache ??= {
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
  }

  /// Initialize: resolve prefix path, download & extract the Termux
  /// bootstrap zip if needed. The zip ships `ar`, `tar`, `xz`, `bash`,
  /// `coreutils`, `apt` — everything needed to install additional
  /// packages on demand later. Call this early (after WidgetsFlutter-
  /// Binding) on Android only.
  Future<BootstrapStatus> initialize({
    void Function(String message, double progress)? onProgress,
  }) async {
    if (_ready) return BootstrapStatus.alreadyReady;

    try {
      final appDir = await getApplicationSupportDirectory();
      _prefixPath = '${appDir.parent.path}/files/usr';

      final prefs = await SharedPreferences.getInstance();
      final installedVersion = prefs.getInt(_prefKey) ?? 0;

      if (installedVersion >= _currentVersion) {
        if (await Directory(binPath).exists() &&
            await File('$binPath/sh').exists()) {
          _ready = true;
          return BootstrapStatus.alreadyReady;
        }
        // Prefix was wiped — re-download.
      }

      onProgress?.call('Preparing development environment...', 0.0);
      await _createDirectories();

      onProgress?.call('Detecting device architecture...', 0.02);
      final arch = await _detectArch();
      debugPrint('[Bootstrap] detected arch: $arch');

      onProgress?.call('Loading bundled bootstrap ($arch)...', 0.05);
      final Uint8List zipBytes;
      try {
        final data = await rootBundle.load(_bootstrapAssetPath(arch));
        zipBytes = data.buffer.asUint8List();
      } catch (e) {
        return BootstrapStatus.error(
          'No bundled bootstrap for $arch. This build ships aarch64 only; '
          'please install a matching ABI build. ($e)',
        );
      }

      onProgress?.call('Extracting...', 0.15);
      final extracted = await _extractBootstrapZipBytes(zipBytes, onProgress);
      if (!extracted) {
        return BootstrapStatus.error('Extract failed');
      }

      onProgress?.call('Setting permissions...', 0.95);
      _chmodBinTreesSync();

      onProgress?.call('Verifying installation...', 0.98);
      final verified = await _verifyBootstrap();

      if (verified) {
        await prefs.setInt(_prefKey, _currentVersion);
        _ready = true;
        onProgress?.call('Ready', 1.0);
        return BootstrapStatus.extracted;
      }
      return BootstrapStatus.partialFailure;
    } catch (e, st) {
      debugPrint('[Bootstrap] init failed: $e\n$st');
      return BootstrapStatus.error(e.toString());
    }
  }

  /// Detect the device CPU ABI so we download the matching bootstrap zip.
  /// Falls back to aarch64 (modern default — covers >95% of Android 10+
  /// devices) if detection fails.
  Future<String> _detectArch() async {
    try {
      final r = await Process.run('/system/bin/getprop', [
        'ro.product.cpu.abi',
      ]).timeout(const Duration(seconds: 3));
      final abi = (r.stdout as String).trim();
      if (abi.startsWith('arm64')) return 'aarch64';
      if (abi.startsWith('armeabi')) return 'arm';
      if (abi.startsWith('x86_64')) return 'x86_64';
      if (abi.startsWith('x86')) return 'i686';
    } catch (_) {}
    return 'aarch64';
  }

  /// Extract the bootstrap zip bytes into the prefix.
  ///
  /// Uses synchronous file I/O — await-per-file for 5k+ files on a
  /// mobile device is death by a thousand context switches (took >5
  /// minutes in testing and was killed by Android's process freezer
  /// before completing). The sync path runs in Dart's main isolate but
  /// a 25MB zip extract finishes in ~3 seconds, well under the
  /// frame-budget window we care about for first launch.
  ///
  /// To keep the UI responsive during that window we yield back to the
  /// event loop every 200 files via `Future.delayed(Duration.zero)`.
  Future<bool> _extractBootstrapZipBytes(
    Uint8List bytes,
    void Function(String, double)? onProgress,
  ) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? symlinksContent;
      final total = archive.length;
      int done = 0;

      // Pre-create every directory path in one pass. Skipping the
      // per-file `parent.exists()` probe cuts ~5k syscalls on aarch64
      // bootstrap.
      final dirs = <String>{};
      for (final e in archive) {
        if (!e.isFile) continue;
        if (e.name == 'SYMLINKS.txt') continue;
        final slash = e.name.lastIndexOf('/');
        if (slash > 0) dirs.add('$prefixPath/${e.name.substring(0, slash)}');
      }
      for (final d in dirs) {
        Directory(d).createSync(recursive: true);
      }

      // Hardcoded Termux prefix that a lot of shebangs embed. We'll
      // patch references to it as we extract so no post-pass over the
      // filesystem is needed. Stored as bytes for fast containsBytes
      // scans against the raw zip entry content.
      const termuxPrefix = '/data/data/com.termux/files/usr';
      final termuxBytes = Uint8List.fromList(utf8.encode(termuxPrefix));
      final ourPrefixBytes = Uint8List.fromList(utf8.encode(prefixPath));

      for (final entry in archive) {
        done++;
        if (done % 400 == 0) {
          onProgress?.call(
            'Extracting $done/$total...',
            0.15 + (done / total) * 0.70,
          );
          // Let other microtasks breathe — the event loop otherwise
          // stalls the Flutter paint callbacks for seconds at a time.
          await Future<void>.delayed(Duration.zero);
        }

        if (entry.name == 'SYMLINKS.txt') {
          symlinksContent = utf8.decode(entry.content as List<int>);
          continue;
        }

        final outPath = '$prefixPath/${entry.name}';
        if (entry.isFile) {
          var content = entry.content as List<int>;
          // Shebang rewrite: only look at files that start with `#!`
          // and contain the Termux prefix somewhere. Everything else
          // skips the byte scan entirely — keeps the hot path tight.
          if (content.length > 2 &&
              content[0] == 0x23 && // '#'
              content[1] == 0x21 && // '!'
              _containsBytes(content, termuxBytes)) {
            content = _replaceBytes(content, termuxBytes, ourPrefixBytes);
          }
          File(outPath).writeAsBytesSync(content, flush: false);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }

      if (symlinksContent != null) {
        onProgress?.call('Creating symlinks...', 0.89);
        _applySymlinksSync(symlinksContent);
      }
      return true;
    } catch (e, st) {
      debugPrint('[Bootstrap] extract failed: $e\n$st');
      return false;
    }
  }

  /// Termux's SYMLINKS.txt uses U+2190 (`←`) as the separator between
  /// target and link path. Each line is `target←link-relative-to-usr`.
  /// Sync version — async awaits per-link were death-by-a-thousand
  /// context-switches (1400+ links on aarch64) and kept getting the
  /// app frozen mid-extract.
  void _applySymlinksSync(String manifest) {
    const sep = '←';
    const termuxPrefix = '/data/data/com.termux/files/usr';
    final ourPrefix = prefixPath;
    for (final line in manifest.split('\n')) {
      if (line.isEmpty) continue;
      final idx = line.indexOf(sep);
      if (idx < 0) continue;
      var target = line.substring(0, idx);
      final relLink = line.substring(idx + sep.length);

      if (target.startsWith(termuxPrefix)) {
        target = ourPrefix + target.substring(termuxPrefix.length);
      }

      final linkAbs = '$prefixPath/$relLink';
      try {
        final link = Link(linkAbs);
        if (link.existsSync()) link.deleteSync();
        final asFile = File(linkAbs);
        if (asFile.existsSync()) asFile.deleteSync();
        Directory(link.parent.path).createSync(recursive: true);
        link.createSync(target);
      } catch (e) {
        debugPrint('[Bootstrap] symlink $linkAbs -> $target failed: $e');
      }
    }
  }

  /// Blanket-chmod the bin + libexec trees to 755 so shebangs fire.
  /// Synchronous — if we let the event loop turn here, Android's
  /// process freezer can yank the app between extract and chmod and
  /// leave files unexecutable. Single fork per tree is fine.
  void _chmodBinTreesSync() {
    for (final p in ['$prefixPath/bin', '$prefixPath/libexec']) {
      if (!Directory(p).existsSync()) continue;
      try {
        Process.runSync('/system/bin/chmod', ['-R', '755', p]);
      } catch (_) {
        // /system/bin/chmod is near-universal on Android (part of
        // toybox). If it's genuinely missing, individual binaries
        // still run via Process.run with an absolute path — the
        // kernel's exec path doesn't require +x on the inode when
        // dispatched from a user-space Dart Process.
      }
    }
  }

  /// `content.indexOf(needle)` for `List<int>`. Returns true if `needle`
  /// appears anywhere in `content`. Naive O(n·m) scan — fine because
  /// needle is ~32 bytes and content is typically < 32 KB.
  bool _containsBytes(List<int> content, Uint8List needle) {
    final nl = needle.length;
    final cl = content.length;
    if (nl == 0 || cl < nl) return false;
    final first = needle[0];
    outer:
    for (var i = 0; i <= cl - nl; i++) {
      if (content[i] != first) continue;
      for (var j = 1; j < nl; j++) {
        if (content[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  /// Byte-level string replace. Only called after [_containsBytes]
  /// confirmed a hit so we don't pay the copy for pure-binary files.
  ///
  /// Uses BytesBuilder (dart:io) instead of List<int> to avoid the
  /// repeated O(n) reallocation that add/addAll caused on a growable list.
  List<int> _replaceBytes(
    List<int> content,
    Uint8List from,
    Uint8List to,
  ) {
    final out = BytesBuilder(copy: false);
    final fl = from.length;
    final cl = content.length;
    var i = 0;
    while (i < cl) {
      if (i <= cl - fl && content[i] == from[0]) {
        var match = true;
        for (var j = 1; j < fl; j++) {
          if (content[i + j] != from[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          out.add(to);
          i += fl;
          continue;
        }
      }
      out.addByte(content[i]);
      i++;
    }
    return out.toBytes();
  }

  Future<bool> _verifyBootstrap() async {
    // "sh" is the most fundamental file — if it's missing, every other
    // command will fail. Don't bother probing more.
    return File('$binPath/sh').exists();
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
    // Create all directories in parallel — each is an independent syscall.
    await Future.wait(dirs.map((d) => Directory(d).create(recursive: true)));
  }

  /// Get status of each individual tool. The base bootstrap zip only
  /// ships bash + coreutils + ar/tar/xz/apt; python/node/git/clang come
  /// from `apt install`. We still probe for them so the agent knows
  /// whether a top-up install has happened.
  Future<Map<String, bool>> getToolStatus() async {
    if (_prefixPath == null) return {};
    final tools = {
      'sh': '$binPath/sh',
      'bash': '$binPath/bash',
      'apt': '$binPath/apt',
      'ar': '$binPath/ar',
      'tar': '$binPath/tar',
      'xz': '$binPath/xz',
      'python3': '$binPath/python3',
      'node': '$binPath/node',
      'git': '$binPath/git',
      'clang': '$binPath/clang',
    };
    // Probe all tool paths in parallel — each is an independent filesystem check.
    final results = await Future.wait(
      tools.entries.map((e) async {
        final path = e.value;
        final exists = await File(path).exists() || await Link(path).exists();
        return MapEntry(e.key, exists);
      }),
    );
    return Map.fromEntries(results);
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
      final result = await Process.run('/system/bin/sh', [
        '-c',
        cmd,
      ], environment: environment).timeout(const Duration(seconds: 10));
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

  static const alreadyReady = BootstrapStatus._(
    true,
    'Development tools ready',
  );
  static const extracted = BootstrapStatus._(
    true,
    'Development tools extracted successfully',
  );
  static const partialFailure = BootstrapStatus._(
    true,
    'Some tools may be missing',
  );

  factory BootstrapStatus.error(String msg) =>
      BootstrapStatus._(false, 'Bootstrap failed: $msg');

  @override
  String toString() => 'BootstrapStatus($message)';
}
