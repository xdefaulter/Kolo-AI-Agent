import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/provider.dart';
import '../tools/tool_base.dart';
import '../tools/tool_registry.dart';
import '../permissions/permission_manager.dart';
import '../../core/providers_state.dart';
import '../../core/storage/database.dart';
import 'agent_loop.dart';
import 'conversation_manager.dart';
import 'system_prompt.dart';
import 'tool_router.dart';
import '../providers.dart';
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
  }

  /// Get the active API provider from settings (reads from same provider UI uses)
  ApiProvider? get _activeProvider {
    final providers = _ref.read(providersProvider);

    if (providers.isEmpty) return null;
    final providerConfig = providers.firstWhere(
      (p) => p.isActive,
      orElse: () => providers.first,
    );

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
    );
  }

  /// Get tool definitions for the API call — only enabled tools
  List<Map<String, dynamic>> get _toolDefinitions =>
      registry.getFunctionDefinitions(
        isEnabled: (name) => permissionManager.isEnabled(name),
      );

  /// Get messages trimmed to token budget
  List<Map<String, dynamic>> get _messagesForApi =>
      conversationManager.getMessagesForApi(
        systemPrompt: SystemPromptBuilder.build(
          customInstructions: _ref.read(customInstructionsProvider),
        ),
      );

  /// Send a user message and run the full agent loop — yields events in real-time
  Stream<AgentEvent> sendMessage(String text, {List<ChatAttachment>? imageAttachments}) async* {
    final provider = _activeProvider;
    if (provider == null) {
      yield AgentError(error: 'No API provider configured. Go to Settings to add one.');
      return;
    }

    if (registry.all.isEmpty) {
      yield AgentError(error: 'No tools registered.');
      return;
    }

    // Create a fresh cancel token for this run
    _cancelToken = Completer<void>();

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
          'image_url': {
            'url': 'data:${att.mimeType};base64,${att.base64Data}',
          },
        });
      }
      conversationManager.addUserMessageMultimodal(contentParts);
    } else {
      conversationManager.addUserMessage(text);
    }

    // Create the agent loop with cancel token
    final maxIter = _ref.read(maxIterationsProvider);

    final agentLoop = AgentLoop(
      toolRouter: ToolRouter(
        registry: registry,
        permissionManager: permissionManager,
      ),
      provider: provider,
      cancelToken: _cancelToken,
      maxIterations: maxIter,
    );

    // Run the loop — events stream out in real-time
    await for (final event in agentLoop.run(
      messages: _messagesForApi,
      chatId: _ref.read(activeChatIdProvider),
      toolDefinitions: _toolDefinitions,
    )) {
      // Sync conversation manager with what the loop produces
      if (event is AgentTextComplete) {
        conversationManager.addAssistantMessage(event.content);
      } else if (event is AgentToolResult) {
        conversationManager.addToolResultMessage(
          event.toolCallId,
          event.result.success ? event.result.output : 'Error: ${event.result.error}',
        );
      } else if (event is AgentToolCallsStart) {
        conversationManager.addAssistantToolCallMessage(
          '',
          event.calls.map((tc) => {
            'id': tc.id,
            'type': 'function',
            'function': {'name': tc.name, 'arguments': tc.arguments},
          }).toList(),
        );
      } else if (event is AgentCancelled) {
        // Preserve partial content
        if (event.partialContent.isNotEmpty) {
          conversationManager.addAssistantMessage('${event.partialContent} [cancelled]');
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

  /// Set the user permission prompt callback (called from UI)
  void setPermissionCallbacks({
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)? promptUser,
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)? biometricPrompt,
  }) {
    permissionManager.promptUser = promptUser;
    permissionManager.biometricPrompt = biometricPrompt;
  }

  /// Load messages into the conversation manager (for chat switch)
  void loadMessages(List<ChatMessage> messages) {
    conversationManager.clear();
    for (final msg in messages) {
      conversationManager.addMessage(msg);
    }
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
final agentSessionProvider = StateNotifierProvider<AgentSessionNotifier, AgentSessionState>((ref) {
  return AgentSessionNotifier(ref);
});

class AgentSessionNotifier extends StateNotifier<AgentSessionState> {
  final Ref _ref;
  AgentSession? _session;

  AgentSessionNotifier(this._ref) : super(const AgentSessionIdle());

  AgentSession? get session => _session;

  /// Initialize the session with a tool registry
  void init(ToolRegistry registry) {
    _session = AgentSession.create(_ref, registry);
  }

  /// Send a message through the agent loop — streams UI updates in real-time
  Future<void> sendMessage(String text, {List<ChatAttachment>? imageAttachments}) async {
    if (_session == null) {
      state = const AgentSessionError('Session not initialized');
      return;
    }

    if (text.trim().isEmpty) return;

    state = const AgentSessionRunning(
      currentContent: '',
      currentThinking: '',
      toolCalls: [],
      toolResults: [],
    );

    final buffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final toolCalls = <AgentToolCallsStart>[];
    final toolResults = <AgentToolResult>[];

    try {
      // Subscribe to the stream and update state on every event
      final stream = _session!.sendMessage(text, imageAttachments: imageAttachments);
      await for (final event in stream) {
        if (state is! AgentSessionRunning && state is! AgentSessionError) {
          // Cancelled or completed — stop processing
          break;
        }
        switch (event) {
          case AgentThinkingChunk():
            thinkingBuffer.write(event.thinking);
            state = AgentSessionRunning(
              currentContent: buffer.toString(),
              currentThinking: thinkingBuffer.toString(),
              toolCalls: toolCalls,
              toolResults: toolResults,
            );
          case AgentContentChunk():
            buffer.write(event.content);
            state = AgentSessionRunning(
              currentContent: buffer.toString(),
              currentThinking: thinkingBuffer.toString(),
              toolCalls: toolCalls,
              toolResults: toolResults,
            );
          case AgentTextComplete():
            state = AgentSessionCompleted(
              content: event.content,
              thinkingContent: thinkingBuffer.toString(),
              toolCalls: toolCalls,
              toolResults: toolResults,
            );
          case AgentToolCallsStart():
            toolCalls.add(event);
            state = AgentSessionRunning(
              currentContent: buffer.toString(),
              currentThinking: thinkingBuffer.toString(),
              toolCalls: List.unmodifiable(toolCalls),
              toolResults: toolResults,
            );
          case AgentToolResult():
            toolResults.add(event);
            state = AgentSessionRunning(
              currentContent: buffer.toString(),
              currentThinking: thinkingBuffer.toString(),
              toolCalls: toolCalls,
              toolResults: List.unmodifiable(toolResults),
            );
          case AgentError():
            state = AgentSessionError(event.error);
          case AgentCancelled():
            if (event.partialContent.isNotEmpty) {
              state = AgentSessionCompleted(
                content: event.partialContent,
                thinkingContent: thinkingBuffer.toString(),
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
  }

  /// Load messages into the session (for chat switch)
  void loadMessages(List<ChatMessage> messages) {
    _session?.loadMessages(messages);
  }

  /// Set permission callbacks
  void setPermissionCallbacks({
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)? promptUser,
    Future<bool> Function(String, Map<String, dynamic>, ToolPermission)? biometricPrompt,
  }) {
    _session?.setPermissionCallbacks(promptUser: promptUser, biometricPrompt: biometricPrompt);
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