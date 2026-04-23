import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'provider.dart';

/// OpenAI-compatible API client with streaming support
class OpenAIClient {
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
      : _dio = Dio(BaseOptions(
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
        )) {
    // Re-attach auth headers on redirects (Dio strips Authorization on cross-origin redirects)
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer ${provider.apiKey}';
        handler.next(options);
      },
    ));
  }

  /// Cancel any active stream
  void cancel() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
  }

  /// Evict stale idle connections from the Dio connection pool.
  /// Safe to call on app resume — does NOT destroy the adapter.
  void closeConnections() {
    // close(force:true) permanently kills the adapter, causing all subsequent
    // requests to fail. Instead, just create a new adapter to discard stale
    // pooled connections while keeping the Dio instance usable.
    _dio.httpClientAdapter = HttpClientAdapter();
  }

  /// Send a streaming chat completion request
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
          String errorBody = '';
          await for (final chunk in response.data!.stream) {
            errorBody += utf8.decode(chunk, allowMalformed: true);
          }
          String detail = _extractErrorDetail(errorBody);
          yield ChatStreamChunk(
            content: '',
            finishReason: 'error',
            error: 'Authentication failed (HTTP ${response.statusCode}): $detail',
          );
          return;
        }

        // Handle retryable server errors
        if (response.statusCode != null && response.statusCode! >= 500) {
          if (attempt < _maxRetries) {
            await _backoff(attempt);
            continue;
          }
          // Drain the error response stream
          await for (final _ in response.data!.stream) {}
          yield ChatStreamChunk(
            content: '',
            finishReason: 'error',
            error: 'Server error (HTTP ${response.statusCode}) after ${_maxRetries + 1} attempts',
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
            error: 'Rate limited (HTTP 429) after ${_maxRetries + 1} attempts. Try again later.',
          );
          return;
        }

        // Handle other client errors (4xx) — don't retry
        if (response.statusCode != null && response.statusCode! >= 400) {
          String errorBody = '';
          await for (final chunk in response.data!.stream) {
            errorBody += utf8.decode(chunk, allowMalformed: true);
          }
          String detail = _extractErrorDetail(errorBody);
          yield ChatStreamChunk(
            content: '',
            finishReason: 'error',
            error: 'API Error (HTTP ${response.statusCode}): $detail',
          );
          return;
        }

        // Success — process the SSE stream
        String buffer = '';
        await for (final chunk in response.data!.stream) {
          final decoded = utf8.decode(chunk, allowMalformed: true);
          buffer += decoded;

          while (buffer.contains('\n')) {
            final idx = buffer.indexOf('\n');
            final line = buffer.substring(0, idx).trim();
            buffer = buffer.substring(idx + 1);

            if (line.isEmpty || line.startsWith(':')) continue;
            if (!line.startsWith('data: ')) continue;

            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              return;
            }

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List<dynamic>?;
              if (choices == null || choices.isEmpty) continue;

              final choice = choices[0] as Map<String, dynamic>;
              final delta = choice['delta'] as Map<String, dynamic>? ?? {};
              final content = delta['content'] as String? ?? '';
              final reasoningContent = delta['reasoning_content'] as String? ??
                  delta['reasoning'] as String? ?? '';
              final toolCalls = delta['tool_calls'] as List<dynamic>?;
              final finishReason = choice['finish_reason'] as String?;

              yield ChatStreamChunk(
                content: content,
                reasoningContent: reasoningContent.isNotEmpty ? reasoningContent : null,
                toolCalls: toolCalls
                    ?.map((tc) => ToolCallDelta.fromJson(tc as Map<String, dynamic>))
                    .toList(),
                finishReason: finishReason,
              );
            } catch (_) {
              // Skip malformed chunks
            }
          }
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
          errorDetail = 'HTTP $statusCode${detail.isNotEmpty ? ': $detail' : ''} | ${provider.baseUrl} | model: ${provider.model}';
        } else {
          errorDetail = '${e.message ?? e.type.toString()} | ${provider.baseUrl}';
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
  }

  /// Send a non-streaming request
  Future<Map<String, dynamic>> chatComplete({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    final requestBody = <String, dynamic>{
      'model': provider.model,
      'messages': messages,
      'max_tokens': provider.maxTokens,
      'temperature': provider.temperature,
    };
    if (tools.isNotEmpty) {
      requestBody['tools'] = tools;
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/completions',
      data: requestBody,
    );
    if (response.statusCode != null && response.statusCode! >= 400) {
      final body = response.data;
      String detail = '';
      if (body != null && body['error'] is Map) {
        detail = (body['error'] as Map?)?['message']?.toString() ?? body.toString();
      }
      throw Exception('HTTP ${response.statusCode}: $detail');
    }
    return response.data!;
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
  final List<ToolCallDelta>? toolCalls;
  final String? finishReason;
  final String? error;

  ChatStreamChunk({
    required this.content,
    this.reasoningContent,
    this.toolCalls,
    this.finishReason,
    this.error,
  });
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
