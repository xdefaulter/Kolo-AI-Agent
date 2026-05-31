import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../bootstrap/bootstrap_service.dart';

/// Observable state of the llama-server process.
enum LlamaServerState {
  /// Termux bootstrap hasn't finished yet, so we can't even check.
  bootstrapPending,

  /// Bootstrap is ready but `llama-server` binary isn't on disk yet.
  /// [LlamaServerService.install] moves us from this state to [stopped].
  notInstalled,

  /// Binary exists but we haven't launched it.
  stopped,

  /// Currently running `apt install llama-cpp -y`. Progress messages
  /// stream through the `onLog` callback.
  installing,

  /// Process is spawned but the /health endpoint hasn't responded yet —
  /// first-launch takes a few seconds while the model loads.
  starting,

  /// Server is accepting requests on [LlamaServerService.port].
  running,

  /// Server exited unexpectedly; last stderr line lives in [lastError].
  crashed,
}

/// Single-source-of-truth lifecycle manager for `llama-server`.
///
/// We deliberately avoid writing our own llama.cpp FFI binding — the
/// Termux package ships the reference llama-server binary (always
/// HEAD-of-main), which speaks OpenAI's HTTP dialect natively
/// (including tool-calling, grammars, and vision). Our agent loop
/// already targets that dialect for cloud providers, so a local
/// provider is just "OpenAIClient pointed at 127.0.0.1:$port".
///
/// What this class owns:
///   * `isInstalled()` — check if `$PREFIX/bin/llama-server` exists
///   * `install()` — run `apt install -y llama-cpp` and stream progress
///   * `start(modelPath)` — spawn the server and wait for /health
///   * `stop()` — SIGTERM the process and clear state
///   * `port` / `baseUrl` — address to point OpenAIClient at
class LlamaServerService {
  LlamaServerService._();
  static final LlamaServerService instance = LlamaServerService._();

  static const _termuxRepoBase =
      'https://packages-cf.termux.dev/apt/termux-main';
  static const _termuxPackagesUrl =
      '$_termuxRepoBase/dists/stable/main/binary-aarch64/Packages';
  static const _downloadHeaders = {'User-Agent': 'curl/8.14.1'};

  /// Fixed loopback port. High enough to avoid clashing with common
  /// ports (8080, 5000, etc.); low-enough-that-SELinux-is-fine on
  /// Android. Randomising per-launch would be slightly safer against
  /// port-sniffers, but same-app-sandbox loopback is already trusted.
  static const int port = 48989;

  /// HTTP base the OpenAIClient should point at.
  String get baseUrl => 'http://127.0.0.1:$port/v1';

  LlamaServerState _state = LlamaServerState.bootstrapPending;
  LlamaServerState get state => _state;

  /// Last unexpected-exit reason, if any. Surfaced in the UI next to
  /// [LlamaServerState.crashed] so the user doesn't have to dig in logs.
  String? lastError;

  /// Path to the currently-loaded model. Null when stopped.
  String? currentModelPath;

  Process? _process;
  final _stateController = StreamController<LlamaServerState>.broadcast();
  Stream<LlamaServerState> get stateStream => _stateController.stream;

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  /// Refresh cached state from disk. Called lazily from the UI; safe
  /// to invoke while a start/stop is in flight (it won't interrupt).
  Future<void> refresh() async {
    if (!BootstrapService.instance.isReady) {
      _setState(LlamaServerState.bootstrapPending);
      return;
    }
    if (!await _binaryExists()) {
      _setState(LlamaServerState.notInstalled);
      return;
    }
    // If a process is actively running we leave the state alone.
    if (_process == null && _state != LlamaServerState.running) {
      _setState(LlamaServerState.stopped);
    }
  }

  /// Is `$PREFIX/bin/llama-server` on disk? Works before bootstrap is
  /// ready by returning false — caller should gate on [BootstrapService.isReady].
  Future<bool> _binaryExists() async {
    if (!BootstrapService.instance.isReady) return false;
    return File('${BootstrapService.instance.binPath}/llama-server').exists();
  }

  /// One-shot install via `apt install -y llama-cpp`. Emits progress
  /// lines on [logStream] as apt prints them. Returns true on success.
  /// Safe to call when already installed — apt is idempotent.
  Future<bool> install({bool withVulkan = false}) async {
    if (!BootstrapService.instance.isReady) {
      lastError = 'Termux bootstrap not ready yet — retry in a moment.';
      _setState(LlamaServerState.bootstrapPending);
      return false;
    }
    _setState(LlamaServerState.installing);
    lastError = null;

    final packages = ['llama-cpp'];
    if (withVulkan) packages.add('llama-cpp-backend-vulkan');

    // Update the package index first — packages.termux.dev rotates
    // versions weekly and a stale index 404s individual downloads.
    final updateOk = await _runApt(['update']);
    var installOk = false;
    if (updateOk) {
      installOk = await _runApt(['install', '-y', ...packages]);
    } else {
      _logController.add('[apt update failed; trying direct deb install]');
    }
    if (!installOk) {
      installOk = await _installDebFallback(packages);
    }
    if (!installOk) {
      lastError = 'apt install failed — see logs for details.';
      _setState(LlamaServerState.notInstalled);
      return false;
    }
    if (!await _binaryExists()) {
      lastError = 'apt reported success but llama-server binary is missing.';
      _setState(LlamaServerState.notInstalled);
      return false;
    }
    _setState(LlamaServerState.stopped);
    return true;
  }

  Future<bool> _installDebFallback(List<String> requestedPackages) async {
    final bs = BootstrapService.instance;
    try {
      _logController.add(
        '[fallback] downloading Termux package index with app networking',
      );
      final index = await _loadPackagesIndex();
      final packageMap = _parsePackagesIndex(index);
      final names = <String>['libandroid-spawn', ...requestedPackages];
      final archiveDir = Directory('${bs.prefixPath}/var/cache/apt/archives');
      await archiveDir.create(recursive: true);

      final debPaths = <String>[];
      for (final name in names) {
        final deb = packageMap[name];
        if (deb == null) {
          _logController.add('[fallback] package metadata missing: $name');
          return false;
        }
        final path = '${archiveDir.path}/${deb.fileName}';
        await _downloadDeb(deb, path);
        debPaths.add(path);
      }

      return _runBootstrapCommand('dpkg', ['-i', ...debPaths]);
    } catch (e, st) {
      debugPrint('[llama.cpp fallback install] failed: $e\n$st');
      _logController.add('[fallback] failed: $e');
      return false;
    }
  }

  Future<String> _loadPackagesIndex() async {
    final bs = BootstrapService.instance;
    final localLists = Directory('${bs.prefixPath}/var/lib/apt/lists');
    final localPackages = localLists
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_Packages'))
        .toList();
    localPackages.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
          headers: _downloadHeaders,
          responseType: ResponseType.plain,
        ),
      );
      final response = await dio.get<String>(_termuxPackagesUrl);
      final body = response.data;
      if (body != null && body.contains('\nPackage: llama-cpp\n')) {
        return body;
      }
      throw StateError('Termux Packages response did not include llama-cpp');
    } catch (e) {
      if (localPackages.isNotEmpty) {
        _logController.add('[fallback] using cached Termux package index');
        return localPackages.first.readAsString();
      }
      rethrow;
    }
  }

  Map<String, _DebPackage> _parsePackagesIndex(String index) {
    final out = <String, _DebPackage>{};
    for (final paragraph in index.split(RegExp(r'\n\s*\n'))) {
      final fields = <String, String>{};
      String? currentKey;
      for (final line in paragraph.split('\n')) {
        if (line.isEmpty) continue;
        if (line.startsWith(' ') && currentKey != null) {
          fields[currentKey] = '${fields[currentKey]}\n${line.substring(1)}';
          continue;
        }
        final idx = line.indexOf(':');
        if (idx <= 0) continue;
        currentKey = line.substring(0, idx);
        fields[currentKey] = line.substring(idx + 1).trim();
      }
      final name = fields['Package'];
      final filename = fields['Filename'];
      final sha256Hex = fields['SHA256'];
      if (name == null || filename == null || sha256Hex == null) continue;
      out[name] = _DebPackage(
        name: name,
        filename: filename,
        sha256Hex: sha256Hex,
      );
    }
    return out;
  }

  Future<void> _downloadDeb(_DebPackage deb, String path) async {
    final file = File(path);
    if (await file.exists()) {
      final existingHash = sha256.convert(await file.readAsBytes()).toString();
      if (existingHash == deb.sha256Hex) {
        _logController.add('[fallback] cached ${deb.fileName}');
        return;
      }
      await file.delete();
    }

    final url = '$_termuxRepoBase/${deb.filename}';
    _logController.add('[fallback] downloading ${deb.fileName}');
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
        headers: _downloadHeaders,
      ),
    );
    await dio.download(
      url,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0 && received == total) {
          _logController.add('[fallback] downloaded ${deb.fileName}');
        }
      },
    );

    final actualHash = sha256.convert(await file.readAsBytes()).toString();
    if (actualHash != deb.sha256Hex) {
      await file.delete();
      throw StateError('SHA-256 mismatch for ${deb.fileName}: $actualHash');
    }
  }

  /// Run apt with the full bootstrap environment. Captures stdout/stderr
  /// and tees them to [logStream] so the UI can show live progress.
  Future<bool> _runApt(List<String> args) async {
    final bs = BootstrapService.instance;
    await bs.refreshResolverConfig();
    _logController.add('\$ apt ${args.join(' ')}');
    return _runBootstrapCommand('apt', args);
  }

  Future<bool> _runBootstrapCommand(String command, List<String> args) async {
    final bs = BootstrapService.instance;
    final proc = await Process.start(
      '${bs.binPath}/$command',
      args,
      environment: bs.environment,
      workingDirectory: bs.filesDir,
      runInShell: false,
    );
    // Non-interactive front-end keeps apt from blocking on config prompts.
    proc.stdin.writeln('');
    await proc.stdin.flush();
    await proc.stdin.close();

    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_logController.add, onError: (_) {});
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_logController.add, onError: (_) {});
    final code = await proc.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        proc.kill();
        return -1;
      },
    );
    _logController.add('[$command exit $code]');
    return code == 0;
  }

  /// Launch llama-server bound to the given GGUF path. Waits for the
  /// /health endpoint to return 200 before flipping to [running]; gives
  /// up after [startupTimeout] and moves to [crashed].
  Future<bool> start(
    String modelPath, {
    int contextSize = 4096,
    int threads = 4,
    Duration startupTimeout = const Duration(seconds: 60),
  }) async {
    await stop();
    if (!await _binaryExists()) {
      lastError = 'llama-server not installed yet.';
      _setState(LlamaServerState.notInstalled);
      return false;
    }
    if (!File(modelPath).existsSync()) {
      lastError = 'Model file not found: $modelPath';
      _setState(LlamaServerState.stopped);
      return false;
    }
    _setState(LlamaServerState.starting);
    currentModelPath = modelPath;

    final bs = BootstrapService.instance;
    final args = <String>[
      '-m', modelPath,
      '--host', '127.0.0.1',
      '--port', '$port',
      '--ctx-size', '$contextSize',
      '--threads', '$threads',
      // Accept OpenAI-style tool calls + native grammar constraints.
      '--jinja',
    ];
    _logController.add('\$ llama-server ${args.join(' ')}');
    try {
      _process = await Process.start(
        '${bs.binPath}/llama-server',
        args,
        environment: bs.environment,
        workingDirectory: bs.filesDir,
        runInShell: false,
      );
    } catch (e) {
      lastError = 'Failed to spawn llama-server: $e';
      _setState(LlamaServerState.crashed);
      return false;
    }

    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_logController.add, onError: (_) {});
    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_logController.add, onError: (_) {});
    // Watch for unexpected death so the state reflects reality.
    unawaited(
      _process!.exitCode.then((code) {
        if (_state == LlamaServerState.running ||
            _state == LlamaServerState.starting) {
          lastError = 'llama-server exited with code $code';
          _setState(LlamaServerState.crashed);
        }
        _process = null;
      }),
    );

    if (await _pollHealth(startupTimeout)) {
      _setState(LlamaServerState.running);
      return true;
    }
    lastError =
        'Server did not become ready within ${startupTimeout.inSeconds}s.';
    await stop();
    _setState(LlamaServerState.crashed);
    return false;
  }

  /// Probe /health every 500 ms until it returns 200 or we hit [timeout].
  /// First-launch latency comes from the GGUF mmap + metadata warmup,
  /// typically 2–10 s on mobile. We keep the probe cheap so the user
  /// sees a responsive UI via [stateStream].
  Future<bool> _pollHealth(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
      ),
    );
    while (DateTime.now().isBefore(deadline)) {
      // Bail early if the process died before the endpoint came up.
      if (_process == null) return false;
      try {
        final r = await dio.getUri<void>(
          Uri.parse('http://127.0.0.1:$port/health'),
        );
        if (r.statusCode == 200) return true;
      } catch (_) {
        // Connection refused while starting is expected.
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Best-effort SIGTERM. Safe to call when nothing is running.
  Future<void> stop() async {
    final p = _process;
    if (p == null) return;
    try {
      p.kill(ProcessSignal.sigterm);
      // Give it a beat to clean up model state, then hard-kill if needed.
      final code = await p.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          p.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      _logController.add('[llama-server stopped, exit $code]');
    } catch (e) {
      debugPrint('[llama-server] stop failed: $e');
    }
    _process = null;
    currentModelPath = null;
    _setState(LlamaServerState.stopped);
  }

  void _setState(LlamaServerState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }
}

class _DebPackage {
  const _DebPackage({
    required this.name,
    required this.filename,
    required this.sha256Hex,
  });

  final String name;
  final String filename;
  final String sha256Hex;

  String get fileName => filename.split('/').last;
}
