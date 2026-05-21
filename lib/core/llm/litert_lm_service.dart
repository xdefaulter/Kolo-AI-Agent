import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Observable state of the LiteRT-LM engine.
enum LitertLmState {
  /// No model path set or engine not created yet.
  notLoaded,

  /// A model path is set but engine.initialize() hasn't been called or completed.
  loading,

  /// Engine is initialised and ready for inference.
  running,

  /// Engine encountered an error.
  error,

  /// Engine was explicitly stopped / closed.
  stopped,
}

/// Singleton lifecycle manager for the LiteRT-LM on-device inference engine.
///
/// Uses a MethodChannel to talk to the Kotlin side, which manages the native
/// `com.google.ai.edge.litertlm.Engine`. The Dart side owns state tracking
/// and exposes a high-level streaming API via [chatStream].
class LitertLmService {
  LitertLmService._();
  static final LitertLmService instance = LitertLmService._();

  static const _channel = MethodChannel('com.kolo.ai/litert_lm');

  LitertLmState _state = LitertLmState.notLoaded;
  LitertLmState get state => _state;

  String? _modelPath;
  String? get modelPath => _modelPath;

  String _activeBackend = 'unknown';
  String get activeBackend => _activeBackend;

  String? lastError;

  final _stateController = StreamController<LitertLmState>.broadcast();
  Stream<LitertLmState> get stateStream => _stateController.stream;

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  /// Whether the engine is initialised and ready for inference.
  bool get isReady => _state == LitertLmState.running;

  /// Initialise the engine with the given .litertlm model file.
  /// Must be called on a background thread / isolate — this blocks for
  /// seconds during model loading. Returns true on success.
  Future<bool> initialize(String modelPath, {String? backend}) async {
    _modelPath = modelPath;
    _setState(LitertLmState.loading);
    lastError = null;
    _logController.add(
      '[LiteRT-LM] Initializing engine with model: $modelPath, backend: ${backend ?? "NPU"}',
    );
    try {
      final result = await _channel.invokeMethod<bool>('initialize', {
        'modelPath': modelPath,
        'backend': backend ?? 'NPU',
      });
      if (result == true) {
        _activeBackend =
            await _channel.invokeMethod<String>('getActiveBackend') ??
            'unknown';
        if (_activeBackend != 'NPU') {
          lastError = 'LiteRT-LM initialized on $_activeBackend, expected NPU';
          try {
            await _channel.invokeMethod<void>('close');
          } catch (_) {
            // Best effort cleanup after a backend mismatch.
          }
          _activeBackend = 'unknown';
          _setState(LitertLmState.error);
          _logController.add('[LiteRT-LM] Error: $lastError');
          return false;
        }
        _setState(LitertLmState.running);
        _logController.add('[LiteRT-LM] Engine initialized on NPU.');
        return true;
      } else {
        lastError = 'Engine initialization returned false';
        _setState(LitertLmState.error);
        _logController.add('[LiteRT-LM] Engine initialization failed.');
        return false;
      }
    } on PlatformException catch (e) {
      _activeBackend = 'unknown';
      lastError = e.message ?? e.code;
      _setState(LitertLmState.error);
      _logController.add('[LiteRT-LM] Error: ${e.message}');
      return false;
    } catch (e) {
      _activeBackend = 'unknown';
      lastError = e.toString();
      _setState(LitertLmState.error);
      _logController.add('[LiteRT-LM] Error: $e');
      return false;
    }
  }

  /// Cancel any ongoing inference.
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancelInference');
    } catch (_) {
      // Best effort — native side will handle cleanup.
    }
  }

  /// Close the engine and release resources.
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {
      // Best effort.
    }
    _modelPath = null;
    _activeBackend = 'unknown';
    _setState(LitertLmState.stopped);
  }

  /// Check if a .litertlm file exists at the given path.
  static Future<bool> modelExists(String path) async {
    return File(path).existsSync();
  }

  /// Copy an asset model to app-private storage and return the path.
  /// Used for bundled models.
  static Future<String> copyAssetModel(String assetKey, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final targetPath = '${dir.path}/litert_lm/$filename';
    final file = File(targetPath);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      final data = await rootBundle.load(assetKey);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return targetPath;
  }

  /// List .litertlm files in the app's model directory.
  static Future<List<String>> listModels() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/litert_lm');
    if (!await modelDir.exists()) return [];
    return modelDir
        .list()
        .where((f) => f.path.endsWith('.litertlm'))
        .map((f) => f.path)
        .toList();
  }

  void _setState(LitertLmState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }
}
