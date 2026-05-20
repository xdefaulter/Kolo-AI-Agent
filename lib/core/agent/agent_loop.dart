import 'dart:async';
import '../api/chat_client.dart';
import '../api/openai_client.dart';
import '../api/streaming_parser.dart';
import '../tools/tool_base.dart';
import 'tool_router.dart';

/// The core agent think-act-observe loop
class AgentLoop {
  final ToolRouter toolRouter;
  final ChatClient client;
  final Completer<void>? cancelToken;
  final int maxIterations;

  AgentLoop({
    required this.toolRouter,
    required this.client,
    this.cancelToken,
    this.maxIterations = 20,
  });

  bool get _cancelled => cancelToken?.isCompleted ?? false;

  /// Run the agent loop: sends messages, processes tool calls, feeds results back
  Stream<AgentEvent> run({
    required List<Map<String, dynamic>> messages,
    required String chatId,
    required List<Map<String, dynamic>> toolDefinitions,
  }) async* {
    List<Map<String, dynamic>> currentMessages = List.from(messages);
    int iterations = 0;

    while (iterations < maxIterations && !_cancelled) {
      iterations++;

      final parser = StreamingParser();
      final contentBuffer = StringBuffer();
      List<ResolvedToolCall>? toolCalls;

      try {
        await for (final chunk in client.chatStream(
          messages: currentMessages,
          tools: toolDefinitions,
        )) {
          // Check cancellation on every chunk
          if (_cancelled) {
            final partialContent = contentBuffer.toString();
            if (partialContent.isNotEmpty) {
              yield AgentTextComplete(
                  content: partialContent, wasCancelled: true);
            }
            yield AgentCancelled(partialContent: partialContent);
            return;
          }

          if (chunk.error != null) {
            yield AgentError(error: chunk.error!);
            return;
          }

          contentBuffer.write(chunk.content);

          if (chunk.toolCalls != null) {
            // Typed fast-path — avoids allocating a wrapper Map + nested
            // function Map per delta per SSE chunk just to feed the parser
            // strings it can read directly off ToolCallDelta.
            parser.processToolCallDeltas(chunk.toolCalls!);
          }

          if (chunk.reasoningContent != null &&
              chunk.reasoningContent!.isNotEmpty) {
            yield AgentThinkingChunk(thinking: chunk.reasoningContent!);
          }

          if (chunk.content.isNotEmpty) {
            yield AgentContentChunk(content: chunk.content);
          }

          // Server-authoritative token counts — usually arrives in the
          // final chunk. Fire as a dedicated event so the metrics
          // notifier can commit cumulative totals without the chat UI
          // needing to care about the wire format.
          if (chunk.usage != null) {
            yield AgentUsageUpdate(usage: chunk.usage!);
          }

          if (chunk.finishReason == 'stop') {
            yield AgentTextComplete(content: contentBuffer.toString());
            return;
          }

          if (chunk.finishReason == 'tool_calls') {
            toolCalls = parser.resolveToolCalls();
          }
        }
      } catch (e) {
        if (_cancelled) {
          final partialContent = contentBuffer.toString();
          if (partialContent.isNotEmpty) {
            yield AgentTextComplete(
                content: partialContent, wasCancelled: true);
          }
          yield AgentCancelled(partialContent: partialContent);
          return;
        }
        yield AgentError(error: 'API error: $e');
        return;
      }

      final fullContent = contentBuffer.toString();

      if (_cancelled) {
        if (fullContent.isNotEmpty) {
          yield AgentTextComplete(content: fullContent, wasCancelled: true);
        }
        return;
      }

      if (toolCalls == null || toolCalls.isEmpty) {
        if (fullContent.isNotEmpty) {
          yield AgentTextComplete(content: fullContent);
        }
        return;
      }

      currentMessages.add({
        'role': 'assistant',
        'content': fullContent.isNotEmpty ? fullContent : null,
        'tool_calls': [for (final tc in toolCalls) tc.toApiFormat()],
      });

      yield AgentToolCallsStart(calls: toolCalls);

      // Check cancellation before executing tools
      if (_cancelled) {
        yield AgentCancelled(partialContent: fullContent);
        return;
      }

      final results = await toolRouter.executeToolsParallel(
        calls: toolCalls,
        chatId: chatId,
      );

      for (int i = 0; i < toolCalls.length; i++) {
        final call = toolCalls[i];
        final result = results[i];

        yield AgentToolResult(
          toolName: call.name,
          toolCallId: call.id,
          result: result,
        );

        currentMessages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result.success ? result.output : 'Error: ${result.error}',
        });
      }
    }

    if (_cancelled) {
      yield AgentCancelled(partialContent: '');
    } else {
      yield AgentError(error: 'Max iterations reached ($maxIterations)');
    }
  }
}

abstract class AgentEvent {}

class AgentThinkingChunk extends AgentEvent {
  final String thinking;
  AgentThinkingChunk({required this.thinking});
}

class AgentContentChunk extends AgentEvent {
  final String content;
  AgentContentChunk({required this.content});
}

class AgentTextComplete extends AgentEvent {
  final String content;
  final bool wasCancelled;
  AgentTextComplete({required this.content, this.wasCancelled = false});
}

class AgentToolCallsStart extends AgentEvent {
  final List<ResolvedToolCall> calls;
  AgentToolCallsStart({required this.calls});
}

class AgentToolResult extends AgentEvent {
  final String toolName;
  final String toolCallId;
  final ToolResult result;
  AgentToolResult({
    required this.toolName,
    required this.toolCallId,
    required this.result,
  });
}

class AgentError extends AgentEvent {
  final String error;
  AgentError({required this.error});
}

class AgentCancelled extends AgentEvent {
  final String partialContent;
  AgentCancelled({required this.partialContent});
}

/// Server-authoritative token counts for the just-completed (or in-flight)
/// request. Fired as soon as the streaming provider emits its `usage`
/// payload — usually in the final SSE chunk.
class AgentUsageUpdate extends AgentEvent {
  final TokenUsage usage;
  AgentUsageUpdate({required this.usage});
}
