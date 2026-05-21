import 'package:flutter/services.dart';

import '../llm/litert_lm_service.dart';
import 'chat_client.dart';
import 'openai_client.dart' show ChatStreamChunk;
import 'provider.dart';

/// On-device LiteRT-LM inference client. Implements [ChatClient] so the
/// agent loop can transparently swap between cloud (OpenAI), llama.cpp, and
/// LiteRT-LM backends.
///
/// Unlike [LlamaCppClient] which bridges through a loopback HTTP server,
/// this client talks directly to the LiteRT-LM native engine via
/// MethodChannel — no network hop required, and the model runs on the
/// device's Tensor G5 NPU.
class LitertLmClient implements ChatClient {
  final ApiProvider provider;

  /// MethodChannel for communicating with the Kotlin side.
  static const _methodChannel = MethodChannel('com.kolo.ai/litert_lm');

  LitertLmClient(this.provider);

  @override
  Stream<ChatStreamChunk> chatStream({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async* {
    final service = LitertLmService.instance;

    // Ensure engine is running.
    switch (service.state) {
      case LitertLmState.notLoaded:
      case LitertLmState.stopped:
        final path = provider.modelPath;
        if (path == null || path.isEmpty) {
          yield ChatStreamChunk(
            content: '',
            finishReason: 'error',
            error:
                'No LiteRT-LM model selected. Open Settings → LiteRT-LM '
                'and pick a .litertlm file.',
          );
          return;
        }
        final ok = await service.initialize(path);
        if (!ok) {
          yield ChatStreamChunk(
            content: '',
            finishReason: 'error',
            error:
                'Failed to initialize LiteRT-LM engine: ${service.lastError}',
          );
          return;
        }
        break;
      case LitertLmState.loading:
        yield ChatStreamChunk(
          content: '',
          finishReason: 'error',
          error: 'LiteRT-LM engine is still loading. Try again in a moment.',
        );
        return;
      case LitertLmState.error:
        yield ChatStreamChunk(
          content: '',
          finishReason: 'error',
          error:
              'LiteRT-LM engine error: ${service.lastError}. '
              'Try restarting from Settings.',
        );
        return;
      case LitertLmState.running:
        break;
    }

    // Build system instruction + a plain-text transcript. LiteRT-LM's native
    // tool-calling path is not wired into our Dart ToolRouter yet, so this
    // provider currently behaves as local chat only.
    final systemParts = <String>[];
    final transcript = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] as String?;
      final content = _stringContent(msg['content']);
      if (content.isEmpty) continue;
      if (role == 'system') {
        systemParts.add(content);
        continue;
      }

      final label = switch (role) {
        'assistant' => 'Assistant',
        'tool' => 'Tool',
        'user' => 'User',
        _ => role ?? 'Message',
      };
      transcript
        ..writeln('$label:')
        ..writeln(content)
        ..writeln();
    }

    final systemInstruction = systemParts.join('\n\n');
    final prompt = transcript.toString().trim();

    if (prompt.isEmpty) {
      yield ChatStreamChunk(content: '', finishReason: 'stop');
      return;
    }

    // Use the synchronous native API for now. The EventChannel streaming path
    // needs request IDs and a readiness handshake before it is safe; otherwise
    // fast native responses can be emitted before Dart has subscribed.
    try {
      final response = await _methodChannel.invokeMethod<String>('chatSync', {
        'text': prompt,
        'systemInstruction': systemInstruction,
      });
      final text = response ?? '';
      if (text.isNotEmpty) {
        yield ChatStreamChunk(content: text);
      }
      yield ChatStreamChunk(content: '', finishReason: 'stop');
    } on PlatformException catch (e) {
      yield ChatStreamChunk(
        content: '',
        finishReason: 'error',
        error: 'LiteRT-LM error: ${e.message}',
      );
    } catch (e) {
      yield ChatStreamChunk(
        content: '',
        finishReason: 'error',
        error: 'LiteRT-LM error: $e',
      );
    }
  }

  @override
  void cancel() {
    LitertLmService.instance.cancel();
  }

  @override
  void closeConnections() {
    // No-op for native engine — no HTTP connections to close.
  }

  static String _stringContent(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is List) {
      final parts = <String>[];
      for (final item in raw) {
        if (item is String) {
          parts.add(item);
        } else if (item is Map) {
          final text = item['text'];
          if (text is String) parts.add(text);
        }
      }
      return parts.join('\n');
    }
    return raw.toString();
  }
}
