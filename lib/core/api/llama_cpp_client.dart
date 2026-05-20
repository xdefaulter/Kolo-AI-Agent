import 'dart:async';

import '../llm/llama_server_service.dart';
import 'chat_client.dart';
import 'openai_client.dart';
import 'provider.dart';

/// On-device chat client. Despite the "Llama.cpp" name this is not an
/// FFI binding — it's a loopback HTTP shim around [OpenAIClient] that
/// talks to the Termux-packaged `llama-server` binary, which in turn
/// wraps the reference llama.cpp library.
///
/// This approach buys three things a custom FFI binding couldn't:
///   * Always-HEAD llama.cpp (updated weekly via Termux apt) — model
///     compatibility stays current without us maintaining a submodule.
///   * Native tool-calling + GBNF grammars + vision, as implemented by
///     the upstream `llama-server` OpenAI-compat layer. No custom
///     tool-call parsing code in our tree.
///   * Identical wire format to cloud providers, so the `AgentLoop`
///     path has exactly one set of streaming-parser edge cases to
///     worry about instead of two.
///
/// The on-disk cost moves from "2000 lines of Dart FFI" to "one
/// `apt install llama-cpp` triggered from Settings".
class LlamaCppClient implements ChatClient {
  final ApiProvider provider;
  OpenAIClient? _http;

  LlamaCppClient(this.provider);

  @override
  Stream<ChatStreamChunk> chatStream({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async* {
    final server = LlamaServerService.instance;
    await server.refresh();

    switch (server.state) {
      case LlamaServerState.bootstrapPending:
        yield ChatStreamChunk(
          content: '',
          error: 'Termux bootstrap is still setting up. Please retry shortly.',
        );
        return;
      case LlamaServerState.notInstalled:
        yield ChatStreamChunk(
          content: '',
          error:
              'llama.cpp is not installed yet. Open Settings → Local Model '
              'and tap "Install llama.cpp" to download (~116 MB).',
        );
        return;
      case LlamaServerState.installing:
      case LlamaServerState.starting:
        yield ChatStreamChunk(
          content: '',
          error: 'Local model is still starting up. Try again in a few seconds.',
        );
        return;
      case LlamaServerState.crashed:
        yield ChatStreamChunk(
          content: '',
          error: 'Local model crashed: ${server.lastError ?? "unknown"}. '
              'Restart from Settings.',
        );
        return;
      case LlamaServerState.stopped:
        // No process — auto-start for this turn if we have a model path.
        final path = provider.modelPath;
        if (path == null || path.isEmpty) {
          yield ChatStreamChunk(
            content: '',
            error:
                'No model selected. Open Settings → Local Model and '
                'download a GGUF first.',
          );
          return;
        }
        final started = await server.start(path);
        if (!started) {
          yield ChatStreamChunk(
            content: '',
            error: 'Failed to start llama-server: ${server.lastError}',
          );
          return;
        }
        break;
      case LlamaServerState.running:
        break;
    }

    // Lazy-build an HTTP client pinned to the loopback server. Reuses
    // the existing OpenAIClient retry/streaming/tool-call parsing; the
    // only distinguishing thing about a local provider at this point
    // is the base URL + empty api key.
    _http ??= OpenAIClient(
      ApiProvider(
        id: provider.id,
        name: provider.name,
        baseUrl: server.baseUrl,
        apiKey: '', // llama-server doesn't validate anything
        model: provider.model,
        customHeaders: provider.customHeaders,
        maxTokens: provider.maxTokens,
        temperature: provider.temperature,
        isActive: provider.isActive,
        kind: ProviderKind.openaiCompat,
        disabledTools: provider.disabledTools,
      ),
    );
    yield* _http!.chatStream(messages: messages, tools: tools);
  }

  @override
  void cancel() => _http?.cancel();

  @override
  void closeConnections() => _http?.closeConnections();
}
