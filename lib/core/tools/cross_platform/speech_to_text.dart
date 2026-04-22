import 'dart:async';
import '../tool_base.dart';
import '../../stt_service.dart';

/// Speech-to-text: transcribe voice input from the microphone.
/// Uses the native on-device SpeechRecognizer (Android) / Speech framework (iOS).
class SpeechToTextTool extends KoloTool {
  @override
  String get name => 'speech_to_text';
  @override
  String get description => 'Listen to the microphone and transcribe speech to text. Returns recognized words.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'timeout_seconds': {'type': 'integer', 'description': 'Max listening time in seconds (default 30)'},
      'language': {'type': 'string', 'description': 'Language for recognition (e.g. "en_US", "fr_FR"). Default: system default.'},
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final timeout = params['timeout_seconds'] as int? ?? 30;
    final language = params['language'] as String?;

    final stt = SttService.instance;
    final available = await stt.init();
    if (!available) {
      return ToolResult.err('Speech recognition is not available on this device.');
    }

    final completer = Completer<ToolResult>();
    String? finalText;

    final sub = stt.finalResults.listen((text) {
      finalText = text;
      if (!completer.isCompleted) {
        completer.complete(ToolResult.ok(text.isEmpty ? '(no speech detected)' : text));
      }
    });

    // Auto-cancel after timeout
    final timer = Timer(Duration(seconds: timeout), () {
      if (!completer.isCompleted) {
        stt.stopListening();
        completer.complete(ToolResult.ok(finalText ?? '(timeout — no speech detected)'));
      }
    });

    await stt.startListening(localeId: language);

    final result = await completer.future;
    timer.cancel();
    sub.cancel();
    return result;
  }
}