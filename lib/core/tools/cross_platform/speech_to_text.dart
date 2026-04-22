import 'dart:async';
import '../tool_base.dart';

/// Speech-to-text: transcribe voice input from the microphone.
/// Note: This requires platform-specific setup (microphone permission + speech recognition).
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
    // timeout_seconds and language will be used when SpeechToText is fully wired to the platform layer
    // ignore: unused_local_variable
    final _ = params['timeout_seconds'] as int? ?? 30;
    // ignore: unused_local_variable
    final __ = params['language'] as String?;

    try {
      // SpeechToText must be initialized on the main thread with a Flutter context.
      // We delegate to the platform layer via method channel.
      // For now, return an error guiding the user — actual STT needs UI integration.
      return ToolResult.err(
        'Speech-to-text requires microphone access and UI integration. '
        'This tool is available but needs platform-specific initialization. '
        'Please use the voice input button in the chat input bar instead.',
      );
    } catch (e) {
      return ToolResult.err('Speech recognition failed: $e');
    }
  }
}