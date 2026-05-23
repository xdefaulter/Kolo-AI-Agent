import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/provider.dart';
import '../tools/tool_base.dart';
import '../tools/tool_registry.dart';
import '../tools/skills.dart';
import '../tools/custom_tools_state.dart';
import '../memory/memory_service.dart';
import 'agent_metrics.dart';
import '../tools/android/scan_phone_apps.dart';
import '../permissions/permission_manager.dart';
import '../../core/providers_state.dart';
import '../../core/storage/database.dart';
import '../api/chat_client.dart';
import 'agent_loop.dart';
import 'conversation_manager.dart';
import 'system_prompt.dart';
import 'tool_router.dart';
import '../providers.dart';
import '../connectivity_service.dart';
import 'agent_settings.dart';
import '../../ui/chat/input_bar.dart' show ChatAttachment;

/// AgentSession: The glue between ChatScreen ↔ AgentLoop ↔ ToolRouter
/// Manages conversation history, tool registry, permissions, and streaming state.
class AgentSession {
  final ToolRegistry registry;
  final PermissionManager permissionManager;
  final ConversationManager conversationManager;
  final Ref _ref;

  /// Cancel token for the current run
  Completer<void>? _cancelToken;

  /// Cached chat client (OpenAI-compat HTTP or local llama.cpp) — reused
  /// across messages while the provider id stays the same. Typed against
  /// the [ChatClient] interface so swapping backends doesn't touch the
  /// rest of the session.
  ChatClient? _cachedClient;
  String? _cachedProviderId;

  /// 2.10: Cached tool router — reused across messages. On first access
  /// we also wire its sub-LLM callback so `prompt`-kind custom tools can
  /// fire off one-shot completions against the currently-active provider.
  /// The closure reads `_activeProvider` at call time (not construction
  /// time) so switching providers mid-session works correctly.
  late final ToolRouter _toolRouter = (() {
    final router = ToolRouter(
      registry: registry,
      permissionManager: permissionManager,
    );
    router.setSubLlmCall(_subLlmCall);
    return router;
  })();

  /// Sub-LLM implementation used by custom `prompt`-kind tools. Uses the
  /// same [ChatClient] cache as the main loop — so whatever provider +
  /// model the user has selected (cloud OAI-compat or on-device
  /// llama.cpp) is what the sub-call uses. No tools, no streaming to
  /// UI; just a blocking call that collects the full response.
  Future<String> _subLlmCall({
    required String systemPrompt,
    required String userMessage,
  }) async {
    final provider = _activeProvider;
    if (provider == null) {
      throw StateError(
        'No active API provider — prompt-kind custom tools need one.',
      );
    }
    final client = _getClient(provider);
    final buf = StringBuffer();
    await for (final chunk in client.chatStream(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userMessage},
      ],
      tools: const [],
    )) {
      if (chunk.error != null) {
        throw Exception(chunk.error);
      }
      buf.write(chunk.content);
      if (chunk.finishReason == 'stop' ||
          chunk.finishReason == 'error' ||
          chunk.finishReason == 'cancelled') {
        break;
      }
    }
    return buf.toString();
  }

  /// Cached app intents summary for system prompt injection
  String? _appIntentsSummary;

  /// Cached skills manifest — rebuilt once per session. Skills added
  /// mid-session won't appear until a new chat or app relaunch, which
  /// is fine (the agent can still read them with list_skills + read_skill).
  String? _skillsManifest;

  /// Rebuilt per-turn inside [sendMessage]. Empty when memory recall is
  /// disabled or no memories match. Kept as a field so the `messages` getter
  /// can stay a pure transform without taking args.
  String _memoriesBlock = '';

  AgentSession._({
    required this.registry,
    required this.permissionManager,
    required this.conversationManager,
    required Ref ref,
  }) : _ref = ref;

  /// Create a session with all dependencies wired up
  static AgentSession create(Ref ref, ToolRegistry registry) {
    final permissionManager = PermissionManager();
    final conversationManager = ConversationManager(maxContextTokens: 32000);
    return AgentSession._(
      registry: registry,
      permissionManager: permissionManager,
      conversationManager: conversationManager,
      ref: ref,
    );
  }

  /// Whether the session is currently running
  bool get isRunning => _cancelToken != null && !_cancelToken!.isCompleted;

  /// Cancel the current run
  void cancel() {
    if (_cancelToken != null && !_cancelToken!.isCompleted) {
      _cancelToken!.complete();
    }
    _cachedClient?.cancel();
  }

  /// Force-close idle HTTP connections to prevent stale-socket errors
  /// after app has been in background. Safe to call anytime.
  void closeStaleConnections() {
    _cachedClient?.closeConnections();
  }

  /// Get or create a cached [ChatClient] for the active provider. The
  /// concrete type is decided by [buildChatClient] based on
  /// `provider.kind` — OpenAI-compat HTTP vs local llama.cpp — so this
  /// session code stays backend-agnostic.
  ChatClient _getClient(ApiProvider provider) {
    if (_cachedClient != null && _cachedProviderId == provider.id) {
      return _cachedClient!;
    }
    _cachedClient = buildChatClient(provider);
    _cachedProviderId = provider.id;
    return _cachedClient!;
  }

  /// Resolve the currently-selected provider config in one linear pass.
  /// Returns null only when the user hasn't configured any provider yet.
  ///
  /// Both [_activeProvider] and [_toolDefinitions] used to do this lookup
  /// independently via `.firstWhere(...)` on every send — meaning each
  /// turn paid two O(n) scans + an extra Riverpod read for the same
  /// answer. Calling this once and reusing the result is cheaper and
  /// also avoids the case where the two getters could see different
  /// states if the user switched providers between them.
  ProviderConfig? _resolveActiveProviderConfig() {
    final providers = _ref.read(providersProvider);
    if (providers.isEmpty) return null;
    for (final p in providers) {
      if (p.isActive) return p;
    }
    return providers.first;
  }

  /// Get the active API provider from settings (reads from same provider UI uses)
  ApiProvider? get _activeProvider =>
      _activeProviderFromConfig(_resolveActiveProviderConfig());

  ApiProvider? _activeProviderFromConfig(ProviderConfig? providerConfig) {
    if (providerConfig == null) return null;
    final model = providerConfig.activeModel;
    if (model == null) return null;
    return ApiProvider(
      id: providerConfig.id,
      name: providerConfig.name,
      baseUrl: providerConfig.baseUrl,
      apiKey: providerConfig.apiKey,
      model: model.modelId,
      customHeaders: providerConfig.customHeaders,
      maxTokens: model.maxTokens,
      temperature: model.temperature,
      isActive: true,
      kind: providerConfig.kind,
      modelPath: providerConfig.modelPath,
      // ApiProvider only reads from disabledTools; the source Set is
      // already final on ProviderConfig + replaced wholesale on edits,
      // so a defensive copy here was just per-send heap churn.
      disabledTools: providerConfig.disabledTools,
    );
  }

  /// Get tool definitions for the API call.
  ///
  /// Two layers of filtering:
  ///   1. `permissionManager.isEnabled(name)` — global per-tool toggle
  ///      the user sets under Settings → Tools.
  ///   2. Provider-scoped blocklist — `ApiProvider.disabledTools` +
  ///      "small model mode" which auto-hides every `dangerous` tool.
  ///      Lets the user pick a 3B local model and still stay safe
  ///      without globally disabling anything.
  List<Map<String, dynamic>> _toolDefinitionsFor(ProviderConfig? activeConfig) {
    final blocked = activeConfig?.disabledTools ?? const <String>{};
    final smallModel = activeConfig?.smallModelMode ?? false;
    return registry.getFunctionDefinitions(
      isEnabled: (name) {
        if (!permissionManager.isEnabled(name)) return false;
        if (blocked.contains(name)) return false;
        if (smallModel && _isRiskyForSmallModel(name)) return false;
        return true;
      },
    );
  }

  /// Heuristic: which built-in tools small local models (3–7B) tend to
  /// misuse badly. Used when `smallModelMode` is on. Not a hard security
  /// boundary — permissions still gate destructive actions regardless.
  bool _isRiskyForSmallModel(String name) {
    final tool = registry.get(name);
    if (tool == null) return false;
    if (tool.permission == ToolPermission.dangerous) return true;
    // Meta / composed custom tools need multi-step JSON reasoning that
    // small models routinely garble. Block preemptively.
    const metaTools = {'create_tool', 'create_skill', 'delete_custom_tool'};
    return metaTools.contains(name);
  }

  /// Get messages trimmed to token budget
  List<Map<String, dynamic>> get _messagesForApi =>
      conversationManager.getMessagesForApi(
        systemPrompt: SystemPromptBuilder.build(
          customInstructions: _ref.read(customInstructionsProvider),
          appIntentsSummary: _appIntentsSummary,
          skillsManifest: _skillsManifest,
          memoriesBlock: _memoriesBlock,
        ),
      );

  /// Send a user message and run the full agent loop — yields events in real-time
  Stream<AgentEvent> sendMessage(
    String text, {
    List<ChatAttachment>? imageAttachments,
  }) async* {
    // One linear scan for the active config — reused for the ApiProvider
    // build AND the tool-definitions filter below. Used to be two
    // independent `.firstWhere` calls per send.
    final activeConfig = _resolveActiveProviderConfig();
    final provider = _activeProviderFromConfig(activeConfig);
    if (provider == null) {
      yield AgentError(
        error: 'No API provider configured. Go to Settings to add one.',
      );
      return;
    }

    if (registry.isEmpty) {
      yield AgentError(error: 'No tools registered.');
      return;
    }

    // Check connectivity before making API call — skip for local providers
    // that don't need network (llama.cpp loopback).
    final isOnline = _ref.read(isOnlineProvider);
    final needsNetwork = activeConfig?.kind != ProviderKind.localLlama;
    if (!isOnline && needsNetwork) {
      yield AgentError(
        error: 'No internet connection. Check your network and try again.',
      );
      return;
    }

    // Create a fresh cancel token for this run
    _cancelToken = Completer<void>();

    // Run independent per-turn/per-session I/O in parallel to cut TTFR.
    // Each branch is idempotent: cached fields short-circuit to Future.value().
    final skillsEnabled = _ref.read(skillsEnabledProvider);
    final memRecallEnabled = _ref.read(memoryRecallEnabledProvider);

    String? intentsResult = _appIntentsSummary;
    String? skillsResult = _skillsManifest;
    String memoriesResult = '';
    final pendingFutures = <Future<void>>[
      if (_appIntentsSummary == null)
        loadAppIntentsSummary()
            .then<void>((v) => intentsResult = v)
            .catchError((_) {}),
      if (_skillsManifest == null && skillsEnabled)
        listAvailableSkills()
            .then(buildSkillsManifest)
            .then<void>((v) => skillsResult = v)
            .catchError((_) {}),
      // Memory recall runs every turn (query changes); pass cached flag to
      // skip the per-turn DB getSetting round-trip.
      MemoryService.instance
          .buildRecallBlock(text, enabled: memRecallEnabled)
          .then<void>((v) => memoriesResult = v)
          .catchError((_) {}),
    ];
    await Future.wait(pendingFutures);

    _appIntentsSummary = intentsResult;
    _skillsManifest = skillsResult;
    _memoriesBlock = memoriesResult;

    // Add user message to conversation — support vision (images)
    if (imageAttachments != null && imageAttachments.isNotEmpty) {
      // Build multimodal content for vision models
      final contentParts = <Map<String, dynamic>>[];
      if (text.isNotEmpty) {
        contentParts.add({'type': 'text', 'text': text});
      }
      for (final att in imageAttachments) {
        contentParts.add({
          'type': 'image_url',
          'image_url': {'url': 'data:${att.mimeType};base64,${att.base64Data}'},
        });
      }
      conversationManager.addUserMessageMultimodal(contentParts);
    } else {
      conversationManager.addUserMessage(text);
    }

    // Create the agent loop with cancel token
    final maxIter = _ref.read(maxIterationsProvider);

    final agentLoop = AgentLoop(
      toolRouter: _toolRouter,
      client: _getClient(provider),
      cancelToken: _cancelToken,
      maxIterations: maxIter,
    );

    // Run the loop — events stream out in real-time
    await for (final event in agentLoop.run(
      messages: _messagesForApi,
      chatId: _ref.read(activeChatIdProvider),
      toolDefinitions: _toolDefinitionsFor(activeConfig),
    )) {
      // Sync conversation manager with what the loop produces
      if (event is AgentTextComplete) {
        conversationManager.addAssistantMessage(event.content);
      } else if (event is AgentToolResult) {
        conversationManager.addToolResultMessage(
          event.toolCallId,
          event.result.success
              ? event.result.output
              : 'Error: ${event.result.error}',
        );
      } else if (event is AgentToolCallsStart) {
        conversationManager.addAssistantToolCallMessage('', [
          for (final tc in event.calls) tc.toApiFormat(),
        ]);
      } else if (event is AgentCancelled) {
        // Preserve partial content
        if (event.partialContent.isNotEmpty) {
          conversationManager.addAssistantMessage(
            '${event.partialContent} [cancelled]',
          );
        }
      }
      yield event;
    }

    // Clear cancel token after run completes
    _cancelToken = null;
  }

  /// Clear conversation history
  void clearConversation() {
    conversationManager.clear();
  }

  /// Re-run the last user turn. Strips trailing assistant / tool-call /
  /// tool-result messages (typically an error bubble + anything it
  /// produced), then re-invokes the loop over the remaining history.
  /// Safe no-op when the transcript is empty or doesn't end in a user
  /// turn after stripping.
  Stream<AgentEvent> retryLastTurn() async* {
    conversationManager.popTrailingAssistantTurn();
    if (conversationManager.messages.isEmpty ||
        conversationManager.messages.last.role != 'user') {
      yield AgentError(error: 'Nothing to retry.');
      return;
    }
    final activeConfig = _resolveActiveProviderConfig();
    final provider = _activeProviderFromConfig(activeConfig);
    if (provider == null) {
      yield AgentError(error: 'No API provider configured.');
      return;
    }
    final isOnline = _ref.read(isOnlineProvider);
    final needsNetwork = activeConfig?.kind != ProviderKind.localLlama;
    if (!isOnline && needsNetwork) {
      yield AgentError(error: 'No internet connection.');
      return;
    }
    _cancelToken = Completer<void>();
    final maxIter = _ref.read(maxIterationsProvider);
    final loop = AgentLoop(
      toolRouter: _toolRouter,
      client: _getClient(provider),
      cancelToken: _cancelToken,
      maxIterations: maxIter,
    );
    await for (final event in loop.run(
      messages: _messagesForApi,
      chatId: _ref.read(activeChatIdProvider),
      toolDefinitions: _toolDefinitionsFor(activeConfig),
    )) {
      if (event is AgentTextComplete) {
        conversationManager.addAssistantMessage(event.content);
      } else if (event is AgentToolResult) {
        conversationManager.addToolResultMessage(
          event.toolCallId,
          event.result.success
              ? event.result.output
              : 'Error: ${event.result.error}',
        );
      } else if (event is AgentToolCallsStart) {
        conversationManager.addAssistantToolCallMessage('', [
          for (final tc in event.calls) tc.toApiFormat(),
        ]);
      }
      yield event;
    }
    _cancelToken = null;
  }

  /// Truncate the conversation at [index] and re-send with [newText] as
  /// the user message. Caller is responsible for also mutating the
  /// persisted store + the UI list; this only touches in-memory state.
  Stream<AgentEvent> editMessageAt(int index, String newText) async* {
    conversationManager.truncateFrom(index);
    yield* sendMessage(newText);
  }

  /// Set the user permission prompt callback (called from UI)
  void setPermissionCallbacks({
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)?
    promptUser,
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)?
    biometricPrompt,
  }) {
    permissionManager.promptUser = promptUser;
    permissionManager.biometricPrompt = biometricPrompt;
  }

  /// Load messages into the conversation manager (for chat switch)
  void loadMessages(List<ChatMessage> messages) {
    conversationManager.clear();
    // Bulk-add: skip the per-message prune scan that turned chat-switch
    // into O(N²) for histories larger than the in-memory cap.
    conversationManager.addAllMessages(messages);
  }
}

/// Custom instructions provider (user-editable system prompt additions)
/// Loaded from persisted storage at app start
final customInstructionsProvider = StateProvider<String>((ref) => '');

/// Async initializer that loads custom instructions from DB
final customInstructionsInitProvider = FutureProvider<void>((ref) async {
  final saved = await AppDatabase.instance.getSetting('custom_instructions');
  if (saved != null && saved.isNotEmpty) {
    ref.read(customInstructionsProvider.notifier).state = saved;
  }
});

/// Riverpod provider for the agent session
final agentSessionProvider =
    StateNotifierProvider<AgentSessionNotifier, AgentSessionState>((ref) {
      return AgentSessionNotifier(ref);
    });

class AgentSessionNotifier extends StateNotifier<AgentSessionState> {
  final Ref _ref;
  AgentSession? _session;

  /// Throttle: minimum interval between streaming state updates
  static const _throttleInterval = Duration(milliseconds: 50);
  DateTime _lastStateUpdate = DateTime(0);

  AgentSessionNotifier(this._ref) : super(const AgentSessionIdle());

  AgentSession? get session => _session;

  /// Initialize the session with a tool registry
  void init(ToolRegistry registry) {
    _session = AgentSession.create(_ref, registry);
  }

  /// Send a message through the agent loop — streams UI updates in real-time
  Future<void> sendMessage(
    String text, {
    List<ChatAttachment>? imageAttachments,
  }) async {
    if (_session == null) {
      state = const AgentSessionError('Session not initialized');
      return;
    }

    if (text.trim().isEmpty) return;

    // Begin metrics capture — cheap (int + DateTime.now) and happens once
    // per turn. UI widgets watching agentMetricsProvider will see the
    // initial "streaming: true" snapshot.
    _ref.read(agentMetricsProvider.notifier).beginTurn();

    state = const AgentSessionRunning(
      currentContent: '',
      currentThinking: '',
      toolCalls: [],
      toolResults: [],
    );

    final stream = _session!.sendMessage(
      text,
      imageAttachments: imageAttachments,
    );
    await _drive(stream);
  }

  /// Re-run the last user turn. Used by the UI's retry-on-error flow.
  /// Shares the stream-to-state translation with [sendMessage] so tool
  /// cards, streaming, and error rendering all work identically.
  Future<void> retryLast() async {
    if (_session == null) {
      state = const AgentSessionError('Session not initialized');
      return;
    }
    _ref.read(agentMetricsProvider.notifier).beginTurn();
    state = const AgentSessionRunning(
      currentContent: '',
      currentThinking: '',
      toolCalls: [],
      toolResults: [],
    );
    await _drive(_session!.retryLastTurn());
  }

  /// Common stream consumer shared by [sendMessage] and [retryLast].
  /// Translates [AgentEvent]s into state transitions + metrics calls.
  Future<void> _drive(Stream<AgentEvent> stream) async {
    final buffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    // Cache the most recent `toString()` of each buffer keyed by length.
    // A throttled state push re-stringifies BOTH buffers even though
    // typically only one of them grew since the last tick — caching by
    // length lets the unchanged buffer reuse its prior string instead
    // of paying an O(n) copy per push. With long streams this saves
    // megabytes of redundant allocation across a turn.
    String contentStr = '';
    int contentStrLen = 0;
    String thinkingStr = '';
    int thinkingStrLen = 0;
    String contentNow() {
      if (buffer.length == contentStrLen) return contentStr;
      contentStr = buffer.toString();
      contentStrLen = contentStr.length;
      return contentStr;
    }

    String thinkingNow() {
      if (thinkingBuffer.length == thinkingStrLen) return thinkingStr;
      thinkingStr = thinkingBuffer.toString();
      thinkingStrLen = thinkingStr.length;
      return thinkingStr;
    }

    final toolCalls = <AgentToolCallsStart>[];
    final toolResults = <AgentToolResult>[];
    try {
      await for (final event in stream) {
        if (state is! AgentSessionRunning && state is! AgentSessionError) {
          // Cancelled or completed — stop processing
          break;
        }
        switch (event) {
          case AgentThinkingChunk():
            thinkingBuffer.write(event.thinking);
            // Reasoning tokens count toward completion speed too — many
            // providers bill them and users want to see speed during a
            // long "thinking" phase. Cheap increment; throttled inside.
            _ref
                .read(agentMetricsProvider.notifier)
                .onContentDelta(event.thinking.length);
            final now = DateTime.now();
            if (now.difference(_lastStateUpdate) >= _throttleInterval) {
              _lastStateUpdate = now;
              state = AgentSessionRunning(
                currentContent: contentNow(),
                currentThinking: thinkingNow(),
                toolCalls: toolCalls,
                toolResults: toolResults,
              );
            }
          case AgentContentChunk():
            buffer.write(event.content);
            _ref
                .read(agentMetricsProvider.notifier)
                .onContentDelta(event.content.length);
            final now = DateTime.now();
            if (now.difference(_lastStateUpdate) >= _throttleInterval) {
              _lastStateUpdate = now;
              state = AgentSessionRunning(
                currentContent: contentNow(),
                currentThinking: thinkingNow(),
                toolCalls: toolCalls,
                toolResults: toolResults,
              );
            }
          case AgentUsageUpdate():
            // Authoritative counts from the server — override estimate.
            _ref.read(agentMetricsProvider.notifier).onServerUsage(event.usage);
          case AgentTextComplete():
            state = AgentSessionCompleted(
              content: event.content,
              thinkingContent: thinkingNow(),
              toolCalls: toolCalls,
              toolResults: toolResults,
            );
          case AgentToolCallsStart():
            toolCalls.add(event);
            state = AgentSessionRunning(
              currentContent: contentNow(),
              currentThinking: thinkingNow(),
              toolCalls: List.unmodifiable(toolCalls),
              toolResults: toolResults,
            );
          case AgentToolResult():
            toolResults.add(event);
            state = AgentSessionRunning(
              currentContent: contentNow(),
              currentThinking: thinkingNow(),
              toolCalls: toolCalls,
              toolResults: List.unmodifiable(toolResults),
            );
          case AgentError():
            state = AgentSessionError(event.error);
          case AgentCancelled():
            if (event.partialContent.isNotEmpty) {
              state = AgentSessionCompleted(
                content: event.partialContent,
                thinkingContent: thinkingNow(),
                toolCalls: toolCalls,
                toolResults: toolResults,
                wasCancelled: true,
              );
            } else {
              state = const AgentSessionIdle();
            }
        }
      }
    } catch (e) {
      state = AgentSessionError('Unexpected error: $e');
    } finally {
      // Always close out metrics — whether the turn finished normally,
      // errored, or was cancelled. endTurn() is a single snapshot push;
      // no cost if called on an already-idle notifier.
      _ref.read(agentMetricsProvider.notifier).endTurn();
    }
  }

  /// Cancel the current run — actually stops the loop via Completer
  void cancel() {
    _session?.cancel();
  }

  /// Clear the conversation
  void clearConversation() {
    _session?.clearConversation();
    state = const AgentSessionIdle();
    // Reset cumulative metrics on chat clear so the per-chat totals
    // stay accurate. Same reset happens on chat switch via loadMessages.
    _ref.read(agentMetricsProvider.notifier).resetSession();
  }

  /// Load messages into the session (for chat switch)
  void loadMessages(List<ChatMessage> messages) {
    _session?.loadMessages(messages);
  }

  /// Set permission callbacks
  void setPermissionCallbacks({
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)?
    promptUser,
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)?
    biometricPrompt,
  }) {
    _session?.setPermissionCallbacks(
      promptUser: promptUser,
      biometricPrompt: biometricPrompt,
    );
  }
}

/// State of the agent session
sealed class AgentSessionState {
  const AgentSessionState();

  bool get isIdle => this is AgentSessionIdle;
  bool get isRunning => this is AgentSessionRunning;
  bool get isCompleted => this is AgentSessionCompleted;
  bool get isError => this is AgentSessionError;
}

final class AgentSessionIdle extends AgentSessionState {
  const AgentSessionIdle();
}

final class AgentSessionRunning extends AgentSessionState {
  final String currentContent;
  final String currentThinking; // accumulated thinking/reasoning tokens
  final List<AgentToolCallsStart> toolCalls;
  final List<AgentToolResult> toolResults;
  const AgentSessionRunning({
    required this.currentContent,
    this.currentThinking = '',
    required this.toolCalls,
    required this.toolResults,
  });
}

final class AgentSessionCompleted extends AgentSessionState {
  final String content;
  final String thinkingContent; // full thinking at completion
  final List<AgentToolCallsStart> toolCalls;
  final List<AgentToolResult> toolResults;
  final bool wasCancelled;
  const AgentSessionCompleted({
    required this.content,
    this.thinkingContent = '',
    required this.toolCalls,
    required this.toolResults,
    this.wasCancelled = false,
  });
}

final class AgentSessionError extends AgentSessionState {
  final String message;
  const AgentSessionError(this.message);
}
