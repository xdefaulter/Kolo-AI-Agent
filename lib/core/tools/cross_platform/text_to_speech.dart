import 'package:flutter_tts/flutter_tts.dart';
import '../tool_base.dart';

/// Text-to-speech: read text aloud through the device speakers.
class TextToSpeechTool extends KoloTool {
  FlutterTts? _tts;

  @override
  String get name => 'text_to_speech';
  @override
  String get description => 'Read text aloud through the device speakers using text-to-speech.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'Text to speak aloud'},
      'language': {'type': 'string', 'description': 'Language code (e.g. "en-US", "fr-FR"). Default: system default.'},
      'rate': {'type': 'number', 'description': 'Speech rate 0.0-1.0 (default 0.5)'},
      'pitch': {'type': 'number', 'description': 'Pitch 0.5-2.0 (default 1.0)'},
    },
    'required': ['text'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  Future<FlutterTts> _getTts() async {
    if (_tts != null) return _tts!;
    final tts = FlutterTts();
    await tts.awaitSpeakCompletion(true);
    _tts = tts;
    return tts;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final text = params['text'] as String;
    final language = params['language'] as String?;
    final rate = params['rate'] as num?;
    final pitch = params['pitch'] as num?;

    try {
      final tts = await _getTts();
      if (language != null) await tts.setLanguage(language);
      if (rate != null) await tts.setSpeechRate(rate.toDouble());
      if (pitch != null) await tts.setPitch(pitch.toDouble());

      final result = await tts.speak(text);
      if (result == 1) {
        return ToolResult.ok('Speaking: "${text.length > 100 ? "${text.substring(0, 100)}..." : text}"');
      } else {
        return ToolResult.err('TTS failed to start');
      }
    } catch (e) {
      return ToolResult.err('Text-to-speech failed: $e');
    }
  }

  /// Stop TTS and release resources
  Future<void> dispose() async {
    await _tts?.stop();
    _tts = null;
  }
}