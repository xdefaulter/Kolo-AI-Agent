import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'provider.dart';

/// OpenAI-compatible API client with streaming support
class OpenAIClient {
  final Dio _dio;
  final ApiProvider provider;

  OpenAIClient(this.provider)
      : _dio = Dio(BaseOptions(
          baseUrl: provider.baseUrl,
          headers: {
            'Authorization': 'Bearer ${provider.apiKey}',
            'Content-Type': 'application/json',
            ...provider.customHeaders,
          },
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => true, // handle all status codes ourselves
        )) {
    // Re-attach auth headers on redirects (Dio strips Authorization on cross-origin redirects)
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer ${provider.apiKey}';
        handler.next(options);
      },
    ));
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
      // tools from getFunctionDefinitions() already have {"type":"function","function":{...}} structure
      requestBody['tools'] = tools;
    }

    try {
      print('[OpenAIClient] POST ${provider.baseUrl}/chat/completions model=${provider.model} key=${provider.apiKey.isEmpty ? "EMPTY" : "${provider.apiKey.substring(0, 4)}..."}');
      final response = await _dio.post<ResponseBody>(
        '/chat/completions',
        data: requestBody,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );
      print('[OpenAIClient] Response received, status: ${response.statusCode}, has data: ${response.data != null}');

      // Handle non-2xx status codes that slipped through validateStatus
      if (response.statusCode != null && response.statusCode! >= 400) {
        // Read the full error response body
        String errorBody = '';
        await for (final chunk in response.data!.stream) {
          errorBody += utf8.decode(chunk, allowMalformed: true);
        }
        // Try to extract error message from JSON
        String detail = errorBody;
        try {
          final parsed = jsonDecode(errorBody);
          if (parsed is Map && parsed['error'] is Map) {
            detail = parsed['error']['message']?.toString() ?? errorBody.substring(0, errorBody.length > 300 ? 300 : errorBody.length);
          }
        } catch (_) {
          detail = errorBody.length > 300 ? errorBody.substring(0, 300) : errorBody;
        }
        final keyHint = provider.apiKey.isEmpty ? ' (no API key!)' : ' (key: ${provider.apiKey.substring(0, provider.apiKey.length > 8 ? 4 : 0)}...)';
        final errorMsg = 'HTTP ${response.statusCode} ${response.statusMessage ?? ''}: $detail | model: ${provider.model}$keyHint';
        print('[OpenAIClient] Error response: $errorMsg');
        yield ChatStreamChunk(content: '', finishReason: 'error', error: 'API Error: $errorMsg');
        return;
      }

      String buffer = '';
      await for (final chunk in response.data!.stream) {
        final decoded = utf8.decode(chunk, allowMalformed: true);
        buffer += decoded;
        print('[OpenAIClient] Chunk received: ${decoded.length} bytes, total buffer: ${buffer.length}');

        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);

          if (line.isEmpty || line.startsWith(':')) continue;
          if (!line.startsWith('data: ')) continue;

          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            print('[OpenAIClient] Stream done');
            return;
          }

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;

            final choice = choices[0] as Map<String, dynamic>;
            final delta = choice['delta'] as Map<String, dynamic>? ?? {};
            final content = delta['content'] as String? ?? '';
            // Extract reasoning/thinking content (DeepSeek, Kimi, some OpenRouter models)
            final reasoningContent = delta['reasoning_content'] as String? ??
                delta['reasoning'] as String? ?? '';
            final toolCalls = delta['tool_calls'] as List<dynamic>?;
            final finishReason = choice['finish_reason'] as String?;
            if (content.isNotEmpty || reasoningContent.isNotEmpty || (toolCalls != null && toolCalls.isNotEmpty)) {
              print('[OpenAIClient] Yielding: content="${content.substring(0, content.length > 50 ? 50 : content.length)}" reasoning="${reasoningContent.substring(0, reasoningContent.length > 50 ? 50 : reasoningContent.length)}" finish=$finishReason');
            }

            yield ChatStreamChunk(
              content: content,
              reasoningContent: reasoningContent.isNotEmpty ? reasoningContent : null,
              toolCalls: toolCalls
                  ?.map((tc) => ToolCallDelta.fromJson(tc as Map<String, dynamic>))
                  .toList(),
              finishReason: finishReason,
            );
          } catch (e) {
            print('[OpenAIClient] Parse error: $e, line: ${data.substring(0, data.length > 100 ? 100 : data.length)}');
            // Skip malformed chunks
          }
        }
      }
      print('[OpenAIClient] Stream ended naturally, remaining buffer: ${buffer.length} bytes');
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final statusMsg = e.response?.statusMessage ?? '';
      final responseBody = e.response?.data;
      String detail = '';
      // Try to extract a useful error message from the response body
      if (responseBody is Map) {
        final errObj = responseBody['error'];
        if (errObj is Map) {
          detail = errObj['message']?.toString() ?? '';
        } else if (responseBody['message'] != null) {
          detail = responseBody['message'].toString();
        }
      } else if (responseBody is String && responseBody.isNotEmpty) {
        // Try to parse as JSON, fallback to raw string
        try {
          final parsed = jsonDecode(responseBody);
          if (parsed is Map && parsed['error'] is Map) {
            detail = parsed['error']['message']?.toString() ?? responseBody.substring(0, responseBody.length > 300 ? 300 : responseBody.length);
          }
        } catch (_) {
          detail = responseBody.length > 300 ? responseBody.substring(0, 300) : responseBody;
        }
      }
      final keyHint = provider.apiKey.isEmpty ? ' (no API key!)' : ' (key: ${provider.apiKey.substring(0, provider.apiKey.length > 8 ? 4 : 0)}...)';
      String errorDetail;
      if (statusCode != null) {
        errorDetail = 'HTTP $statusCode $statusMsg${detail.isNotEmpty ? ': $detail' : ''} | ${provider.baseUrl} | model: ${provider.model}$keyHint';
      } else {
        errorDetail = '${e.message ?? e.type.toString()} | ${provider.baseUrl}$keyHint';
      }
      print('[OpenAIClient] DioException: $errorDetail');
      yield ChatStreamChunk(
        content: '',
        finishReason: 'error',
        error: 'API Error: $errorDetail',
      );
    } catch (e) {
      print('[OpenAIClient] Unexpected error: $e');
      yield ChatStreamChunk(
        content: '',
        finishReason: 'error',
        error: 'Unexpected error: $e',
      );
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
      // tools from getFunctionDefinitions() already have {"type":"function","function":{...}} structure
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
}

class ChatStreamChunk {
  final String content;
  final String? reasoningContent; // thinking/reasoning tokens from models like DeepSeek, Kimi, etc.
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
    // Some providers (Kimi, Ollama, etc.) send arguments as a parsed JSON
    // object instead of a JSON string. Normalize to string.
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