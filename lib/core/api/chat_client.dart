import 'llama_cpp_client.dart';
import 'openai_client.dart';
import 'provider.dart';

/// Transport-agnostic interface for streaming chat completions.
///
/// Introduced alongside the on-device llama.cpp backend: the agent loop
/// only cares about a `Stream<ChatStreamChunk>` producer, not whether
/// the bytes came from an HTTP call or a native FFI binding. Both
/// [OpenAIClient] and the new `LlamaCppClient` implement this — callers
/// pick an implementation via [ChatClientFactory] based on the active
/// provider's `kind`.
abstract class ChatClient {
  /// Streaming chat completion. Implementations must:
  ///   * yield content chunks as they arrive,
  ///   * yield a `finishReason` of `stop` or `tool_calls` exactly once,
  ///   * yield a final `usage` chunk when token counts are known.
  ///
  /// [messages] is OpenAI-shaped. [tools] is the OpenAI function-def
  /// shape (`[{type: function, function: {name, description, parameters}}]`).
  /// Empty `tools` means "don't use tools this turn".
  Stream<ChatStreamChunk> chatStream({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  });

  /// Cancel any in-flight request. Idempotent; safe to call when no
  /// request is active.
  void cancel();

  /// Invoked from the host app on resume — implementations should drop
  /// any stale connection-pool state here. Default: no-op.
  void closeConnections() {}
}

/// Build a [ChatClient] for [provider] based on its [ProviderKind].
/// Single source of truth for "which backend handles this provider",
/// so AgentSession doesn't need to switch on kind itself.
ChatClient buildChatClient(ApiProvider provider) {
  switch (provider.kind) {
    case ProviderKind.localLlama:
      return LlamaCppClient(provider);
    case ProviderKind.openaiCompat:
      return OpenAIClient(provider);
  }
}
