import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'chat_client.dart';
import 'provider.dart';

/// OpenAI-compatible API client with streaming support.
///
/// Implements [ChatClient] so callers (agent session, custom `prompt`
/// tools, future sub-LLM paths) can be written against the interface
/// and swap in `LlamaCppClient` with zero code changes.
class OpenAIClient implements ChatClient {
  final Dio _dio;
  final ApiProvider provider;

  /// Maximum number of retries for transient errors (429, 500, 502, 503)
  static const _maxRetries = 3;

  /// Reusable Random instance for backoff jitter
  static final _random = Random();

  /// Cancellation token for the current stream
  CancelToken? _cancelToken;

  /// Timeout constants
  static const _connectTimeout = Duration(seconds: 30);
  static const _receiveTimeout = Duration(seconds: 120);
  static const _sendTimeout = Duration(seconds: 30);

  OpenAIClient(this.provider)
    : _dio = Dio(
        BaseOptions(
          baseUrl: provider.baseUrl,
          headers: {
            'Authorization': 'Bearer ${provider.apiKey}',
            'Content-Type': 'application/json',
            ...provider.customHeaders,
          },
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
          sendTimeout: _sendTimeout,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
        ),
      ) {
    // Re-attach auth headers on redirects (Dio strips Authorization on cross-origin redirects)
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Authorization'] = 'Bearer ${provider.apiKey}';
          handler.next(options);
        },
      ),
    );
  }

  /// Cancel any active stream
  @override
  void cancel() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
  }

  /// Evict stale idle connections from the Dio connection pool.
  /// Safe to call on app resume — does NOT destroy the adapter.
  @override
  void closeConnections() {
    // close(force:true) permanently kills the adapter, causing all subsequent
    // requests to fail. Instead, just create a new adapter to discard stale
    // pooled connections while keeping the Dio instance usable.
    _dio.httpClientAdapter = HttpClientAdapter();
  }

  /// Send a streaming chat completion request
  @override
  Stream<ChatStreamChunk> chatStream({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async* {
    final requestBody = <String, dynamic>{
      'model': provider.model,
      'messages': messages,
      'max_tokens': provider.maxTokens,
      'temperature': provider.temperature,
      'stream': true,
    };
    if (tools.isNotEmpty) {
      requestBody['tools'] = tools;
    }

    _cancelToken = CancelToken();

    try {
      for (int attempt = 0; attempt <= _maxRetries; attempt++) {
        try {
          final response = await _dio.post<ResponseBody>(
            '/chat/completions',
            data: requestBody,
            cancelToken: _cancelToken,
            options: Options(
              responseType: ResponseType.stream,
              headers: {'Accept': 'text/event-stream'},
              // Allow all status codes for streaming so we can read error bodies
              validateStatus: (_) => true,
            ),
          );

          // Handle auth errors — never retry these
          if (response.statusCode == 401 || response.statusCode == 403) {
            final errorBody = await _readErrorBody(response.data!.stream);
            String detail = _extractErrorDetail(errorBody);
            yield ChatStreamChunk(
              content: '',
              finishReason: 'error',
              error:
                  'Authentication failed (HTTP ${response.statusCode}): $detail',
            );
            return;
          }

          // Handle retryable server errors
          if (response.statusCode != null && response.statusCode! >= 500) {
            if (attempt < _maxRetries) {
              await _backoff(attempt);
              continue;
            }
            // Drain the error response stream with a bounded timeout
            await _drainStream(response.data!.stream);
            yield ChatStreamChunk(
              content: '',
              finishReason: 'error',
              error:
                  'Server error (HTTP ${response.statusCode}) after ${_maxRetries + 1} attempts',
            );
            return;
          }

          // Handle rate limiting with retry
          if (response.statusCode == 429) {
            if (attempt < _maxRetries) {
              // Try to read Retry-After header
              final retryAfter = response.headers.value('retry-after');
              if (retryAfter != null) {
                final seconds = int.tryParse(retryAfter) ?? (1 << attempt);
                await Future.delayed(Duration(seconds: seconds));
              } else {
                await _backoff(attempt);
              }
              continue;
            }
            yield ChatStreamChunk(
              content: '',
              finishReason: 'error',
              error:
                  'Rate limited (HTTP 429) after ${_maxRetries + 1} attempts. Try again later.',
            );
            return;
          }

          // Handle other client errors (4xx) — don't retry
          if (response.statusCode != null && response.statusCode! >= 400) {
            final errorBody = await _readErrorBody(response.data!.stream);
            String detail = _extractErrorDetail(errorBody);
            yield ChatStreamChunk(
              content: '',
              finishReason: 'error',
              error: 'API Error (HTTP ${response.statusCode}): $detail',
            );
            return;
          }

          // Success — process the SSE stream.
          // `pending` holds any partial trailing line carried over from
          // the previous network chunk. The vast majority of chunks end
          // on a `\n` boundary, so `pending` is empty and we operate
          // directly on the freshly-decoded piece — no StringBuffer
          // materialise-and-clear cycle per chunk, no intermediate copy
          // of the full accumulator on each iteration.
          String pending = '';
          await for (final chunk in response.data!.stream) {
            final piece = utf8.decode(chunk, allowMalformed: true);
            final raw = pending.isEmpty ? piece : (pending + piece);

            int start = 0;
            while (true) {
              final idx = raw.indexOf('\n', start);
              if (idx < 0) break;
              final line = raw.substring(start, idx).trim();
              start = idx + 1;

              if (line.isEmpty || line.startsWith(':')) continue;
              if (!line.startsWith('data: ')) continue;

              final data = line.substring(6).trim();
              if (data == '[DONE]') {
                return;
              }

              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                // Usage may arrive in the final chunk with `choices: []`.
                // We want to emit it even if there's no text delta so the
                // agent session can record authoritative token counts.
                final usage = TokenUsage.fromJson(json['usage']);
                final choices = json['choices'] as List<dynamic>?;
                if (choices == null || choices.isEmpty) {
                  if (usage != null) {
                    yield ChatStreamChunk(content: '', usage: usage);
                  }
                  continue;
                }

                final choice = choices[0] as Map<String, dynamic>;
                final delta = choice['delta'] as Map<String, dynamic>? ?? {};
                final content = delta['content'] as String? ?? '';
                final reasoningContent =
                    delta['reasoning_content'] as String? ??
                    delta['reasoning'] as String? ??
                    '';
                final toolCalls = delta['tool_calls'] as List<dynamic>?;
                final finishReason = choice['finish_reason'] as String?;

                yield ChatStreamChunk(
                  content: content,
                  reasoningContent: reasoningContent.isNotEmpty
                      ? reasoningContent
                      : null,
                  // Stay lazy: the only consumer (`StreamingParser
                  // .processToolCallDeltas`) iterates exactly once.
                  // Materialising via `.toList()` here would allocate
                  // a List wrapper per SSE chunk during tool calls
                  // for nothing.
                  toolCalls: toolCalls?.map(
                    (tc) =>
                        ToolCallDelta.fromJson(tc as Map<String, dynamic>),
                  ),
                  finishReason: finishReason,
                  // Rare case: some providers attach usage to the final
                  // delta chunk instead of a separate choices=[] chunk.
                  usage: usage,
                );
              } catch (_) {
                // Skip malformed chunks
              }
            }
            // Preserve any partial line (no trailing \n) for the next chunk.
            pending = (start < raw.length) ? raw.substring(start) : '';
          }
          // Stream ended naturally
          return;
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            yield ChatStreamChunk(content: '', finishReason: 'cancelled');
            return;
          }

          // Retry on connection/timeout/broken-pipe errors (common after app backgrounding)
          if (attempt < _maxRetries && _isRetryableDioError(e)) {
            await _backoff(attempt);
            continue;
          }

          final statusCode = e.response?.statusCode;
          final responseBody = e.response?.data;
          String detail = '';
          if (responseBody is Map) {
            final errObj = responseBody['error'];
            if (errObj is Map) {
              detail = errObj['message']?.toString() ?? '';
            }
          } else if (responseBody is String && responseBody.isNotEmpty) {
            detail = _extractErrorDetail(responseBody);
          }

          String errorDetail;
          if (statusCode != null) {
            errorDetail =
                'HTTP $statusCode${detail.isNotEmpty ? ': $detail' : ''} | ${provider.baseUrl} | model: ${provider.model}';
          } else {
            errorDetail =
                '${e.message ?? e.type.toString()} | ${provider.baseUrl}';
          }
          yield ChatStreamChunk(
            content: '',
            finishReason: 'error',
            error: 'API Error: $errorDetail',
          );
          return;
        } catch (e) {
          // Catch raw HttpException ("Connection closed while receiving data")
          // and other dart:io errors that escape Dio — retry once if backgrounding-related
          if (attempt < _maxRetries && _isRetryableRawError(e)) {
            await _backoff(attempt);
            continue;
          }
          yield ChatStreamChunk(
            content: '',
            finishReason: 'error',
            error: 'Unexpected error: $e',
          );
          return;
        }
      }
    } finally {
      // Always clear the token so subsequent cancel() calls can't act on a
      // completed request — and so a new stream starts with a fresh token.
      _cancelToken = null;
    }
  }

  /// Read an error body from a response stream with a bounded timeout so a
  /// server that half-closes mid-error can't hang the UI.
  Future<String> _readErrorBody(Stream<List<int>> stream) async {
    final buf = StringBuffer();
    try {
      await for (final chunk in stream.timeout(
        const Duration(seconds: 10),
        onTimeout: (sink) => sink.close(),
      )) {
        buf.write(utf8.decode(chunk, allowMalformed: true));
        if (buf.length > 16 * 1024) break; // cap at 16KB — plenty for error msg
      }
    } catch (_) {
      // stream errors are swallowed — we just return whatever we got
    }
    return buf.toString();
  }

  /// Drain a response stream and discard its contents, bounded.
  Future<void> _drainStream(Stream<List<int>> stream) async {
    try {
      await stream
          .timeout(
            const Duration(seconds: 10),
            onTimeout: (sink) => sink.close(),
          )
          .drain();
    } catch (_) {
      // ignore
    }
  }

  /// Extract error detail from a response body string
  String _extractErrorDetail(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map && parsed['error'] is Map) {
        return parsed['error']['message']?.toString() ??
            body.substring(0, body.length > 300 ? 300 : body.length);
      }
    } catch (_) {}
    return body.length > 300 ? body.substring(0, 300) : body;
  }

  /// Exponential backoff with jitter
  Future<void> _backoff(int attempt) async {
    final baseMs = 1000 * (1 << attempt); // 1s, 2s, 4s
    final jitter = _random.nextInt(500);
    await Future.delayed(Duration(milliseconds: baseMs + jitter));
  }

  /// Whether a DioException is worth retrying (connection issues, timeouts, broken pipes)
  bool _isRetryableDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    // Broken pipe / connection reset — often from OS reclaiming sockets after backgrounding
    final msg = e.message?.toLowerCase() ?? '';
    return msg.contains('connection reset') ||
        msg.contains('broken pipe') ||
        msg.contains('connection closed') ||
        msg.contains('connection aborted');
  }

  /// Whether a raw (non-Dio) exception is a backgrounding-related network error
  bool _isRetryableRawError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('broken pipe') ||
        msg.contains('httpexception');
  }
}

class ChatStreamChunk {
  final String content;
  final String? reasoningContent;
  /// Lazy iterable of tool-call deltas for this chunk. Consumers must
  /// iterate exactly once (which `StreamingParser.processToolCallDeltas`
  /// does) — re-iterating a `MappedIterable` re-runs the JSON-decode
  /// closure and would re-allocate every `ToolCallDelta`.
  final Iterable<ToolCallDelta>? toolCalls;
  final String? finishReason;
  final String? error;

  /// Server-reported token usage. Most OpenAI-compatible providers emit
  /// this in the final SSE chunk (with `choices: []`). When present,
  /// callers should prefer these counts over client-side estimates.
  final TokenUsage? usage;

  ChatStreamChunk({
    required this.content,
    this.reasoningContent,
    this.toolCalls,
    this.finishReason,
    this.error,
    this.usage,
  });
}

/// Authoritative token counts returned by the server at the end of a
/// streaming completion. Cheap to construct + compare; used by
/// [AgentSession] to build per-turn metrics without paying for a
/// client-side re-tokenisation.
class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  static const zero = TokenUsage(
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
  );

  /// Parse from the OpenAI-shape `{prompt_tokens, completion_tokens,
  /// total_tokens}` map. Returns null for missing / malformed input.
  static TokenUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final prompt = raw['prompt_tokens'];
    final completion = raw['completion_tokens'];
    final total = raw['total_tokens'];
    if (prompt is! num || completion is! num) return null;
    return TokenUsage(
      promptTokens: prompt.toInt(),
      completionTokens: completion.toInt(),
      totalTokens: total is num
          ? total.toInt()
          : prompt.toInt() + completion.toInt(),
    );
  }

  TokenUsage operator +(TokenUsage other) => TokenUsage(
    promptTokens: promptTokens + other.promptTokens,
    completionTokens: completionTokens + other.completionTokens,
    totalTokens: totalTokens + other.totalTokens,
  );

  @override
  bool operator ==(Object other) =>
      other is TokenUsage &&
      other.promptTokens == promptTokens &&
      other.completionTokens == completionTokens &&
      other.totalTokens == totalTokens;

  @override
  int get hashCode => Object.hash(promptTokens, completionTokens, totalTokens);
}

class ToolCallDelta {
  final int? index;
  final String? id;
  final String? name;
  final String? arguments;

  ToolCallDelta({this.index, this.id, this.name, this.arguments});

  factory ToolCallDelta.fromJson(Map<String, dynamic> json) {
    final function = json['function'] as Map<String, dynamic>? ?? {};
    final rawArgs = function['arguments'];
    final argsString = rawArgs is String
        ? rawArgs
        : rawArgs != null
        ? jsonEncode(rawArgs)
        : null;
    return ToolCallDelta(
      index: json['index'] as int?,
      id: json['id'] as String?,
      name: function['name'] as String?,
      arguments: argsString,
    );
  }
}
