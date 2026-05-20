import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// Native on-device speech-to-text service.
/// Android: Google SpeechRecognizer | iOS: Apple Speech framework
class SttService {
  static final SttService instance = SttService._();

  SttService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  bool _isAvailable = false;

  /// Whether STT is available on this device
  bool get isAvailable => _isAvailable;

  /// Whether currently listening
  bool get isListening => _speech.isListening;

  /// Stream of partial (interim) recognition results
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();
  Stream<String> get partialResults => _partialController.stream;

  /// Stream of final recognition results
  final StreamController<String> _resultController =
      StreamController<String>.broadcast();
  Stream<String> get finalResults => _resultController.stream;

  /// Initialize the speech engine. Call once at app startup.
  Future<bool> init() async {
    if (_initialized) return _isAvailable;
    _isAvailable = await _speech.initialize(
      onError: _onError,
      onStatus: _onStatus,
      debugLogging: false,
    );
    _initialized = true;
    return _isAvailable;
  }

  /// Start listening for speech.
  /// [localeId] — BCP-47 locale (e.g. 'en_US'). Null = system default.
  /// [listenMode] — Dictation mode for longer-form input.
  Future<void> startListening({String? localeId}) async {
    if (!_initialized) await init();
    if (!_isAvailable || _speech.isListening) return;

    // Clear any pending text
    _partialController.add('');
    _resultController.add('');

    await _speech.listen(
      onResult: _onResult,
      localeId: localeId,
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      cancelOnError: true,
      listenFor: const Duration(seconds: 60), // Max listen duration
      pauseFor: const Duration(seconds: 3), // Auto-stop after 3s silence
    );
  }

  /// Stop listening (triggers final result if any)
  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  /// Cancel listening (discards current result)
  Future<void> cancelListening() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  /// Get available locales for speech recognition
  Future<List<stt.LocaleName>> locales() async {
    if (!_initialized) await init();
    return _speech.locales();
  }

  void _onResult(SpeechRecognitionResult result) {
    // Fire partial (what user is saying right now)
    if (result.recognizedWords.isNotEmpty) {
      _partialController.add(result.recognizedWords);
    }
    // Fire final when engine is done
    if (result.finalResult) {
      _resultController.add(result.recognizedWords);
    }
  }

  void _onError(SpeechRecognitionError error) {
    // Don't fire errors for no-match or interrupted — just stop cleanly
    if (error.errorMsg == 'no_match_error' || error.errorMsg == 'interrupted') {
      return;
    }
    if (!_resultController.isClosed) {
      _resultController.addError(error.errorMsg);
    }
  }

  void _onStatus(String status) {
    // Available: listening, notListening, unavailable, done
    // We handle state transitions via isListening
  }

  /// Release resources held by the STT engine. The singleton is designed to
  /// live for the whole app, but tests / hot-restart / explicit teardown
  /// should call this to avoid leaking the StreamControllers.
  Future<void> dispose() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
    if (!_partialController.isClosed) await _partialController.close();
    if (!_resultController.isClosed) await _resultController.close();
  }
}
