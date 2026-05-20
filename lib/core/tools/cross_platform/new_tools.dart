import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../tool_base.dart';

final HttpClient _sharedHttpClient = HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..idleTimeout = const Duration(seconds: 30);

bool _isBlockedUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    if (host == '169.254.169.254' || host == 'metadata.google.internal') {
      return true;
    }
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0.0.0.0') {
      return true;
    }

    final parts = host.split('.');
    if (parts.length == 4) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      if (a == 10) return true;
      if (a == 172 && b != null && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 169 && b == 254) return true;
    }

    return uri.scheme == 'http' || uri.scheme == 'https' ? false : true;
  } catch (_) {
    return true;
  }
}

class HttpGetTool extends KoloTool {
  @override
  String get name => 'http_get';

  @override
  String get description =>
      'Make an HTTP GET request to a URL and return the response body.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL to request'},
      'headers': {
        'type': 'object',
        'description': 'Optional headers as key-value pairs',
      },
    },
    'required': ['url'],
  };

  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final url = params['url'] as String;
    if (_isBlockedUrl(url)) {
      return ToolResult.err(
        'URL blocked: requests to private/internal addresses are not allowed.',
      );
    }
    final headers = params['headers'] as Map<String, dynamic>? ?? {};
    try {
      final req = await _sharedHttpClient.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v.toString()));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      return ToolResult.ok(body, metadata: {'statusCode': resp.statusCode});
    } catch (e) {
      return ToolResult.err('HTTP GET failed: $e');
    }
  }
}

class HttpPostTool extends KoloTool {
  @override
  String get name => 'http_post';

  @override
  String get description => 'Make an HTTP POST request with a JSON body.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL to post to'},
      'body': {'type': 'object', 'description': 'JSON body'},
      'headers': {'type': 'object', 'description': 'Optional headers'},
    },
    'required': ['url', 'body'],
  };

  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final url = params['url'] as String;
    if (_isBlockedUrl(url)) {
      return ToolResult.err(
        'URL blocked: requests to private/internal addresses are not allowed.',
      );
    }
    final body = params['body'];
    final headers = params['headers'] as Map<String, dynamic>? ?? {};
    try {
      final req = await _sharedHttpClient.postUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v.toString()));
      if (!headers.containsKey('Content-Type')) {
        req.headers.set('Content-Type', 'application/json');
      }
      req.write(jsonEncode(body));
      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      return ToolResult.ok(respBody, metadata: {'statusCode': resp.statusCode});
    } catch (e) {
      return ToolResult.err('HTTP POST failed: $e');
    }
  }
}

class DateTool extends KoloTool {
  @override
  String get name => 'current_datetime';

  @override
  String get description => 'Get the current date, time, and timezone.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'format': {
        'type': 'string',
        'description': 'Optional format (iso, unix, readable)',
      },
    },
    'required': [],
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final now = DateTime.now();
    final format = params['format'] as String? ?? 'readable';
    switch (format) {
      case 'iso':
        return ToolResult.ok(now.toIso8601String());
      case 'unix':
        return ToolResult.ok(now.millisecondsSinceEpoch.toString());
      default:
        return ToolResult.ok('${now.toIso8601String()} (${now.timeZoneName})');
    }
  }
}

class JsonParseTool extends KoloTool {
  @override
  String get name => 'json_parse';

  @override
  String get description => 'Parse and format a JSON string. Validates syntax.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'json': {'type': 'string', 'description': 'JSON string to parse/format'},
    },
    'required': ['json'],
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    try {
      final decoded = jsonDecode(params['json'] as String);
      return ToolResult.ok(const JsonEncoder.withIndent('  ').convert(decoded));
    } catch (e) {
      return ToolResult.err('Invalid JSON: $e');
    }
  }
}

class Base64Tool extends KoloTool {
  @override
  String get name => 'base64';

  @override
  String get description => 'Encode or decode base64 strings.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'input': {'type': 'string', 'description': 'String to encode/decode'},
      'mode': {
        'type': 'string',
        'enum': ['encode', 'decode'],
        'description': 'encode or decode',
      },
    },
    'required': ['input', 'mode'],
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final input = params['input'] as String;
    final mode = params['mode'] as String;
    try {
      if (mode == 'encode') {
        return ToolResult.ok(base64Encode(utf8.encode(input)));
      }
      return ToolResult.ok(utf8.decode(base64Decode(input)));
    } catch (e) {
      return ToolResult.err('Base64 $mode failed: $e');
    }
  }
}

class HashTool extends KoloTool {
  @override
  String get name => 'hash';

  @override
  String get description => 'Compute a hash of a text string.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'input': {'type': 'string', 'description': 'Text to hash'},
      'algorithm': {
        'type': 'string',
        'enum': ['sha256', 'sha1', 'md5'],
        'description': 'Hash algorithm (default sha256)',
      },
    },
    'required': ['input'],
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final input = params['input'] as String;
    final algo = params['algorithm'] as String? ?? 'sha256';
    try {
      final digest = _hashBytes(utf8.encode(input), algo);
      return ToolResult.ok('$algo:${digest.toString()}');
    } catch (e) {
      return ToolResult.err('Hash failed: $e');
    }
  }

  Digest _hashBytes(List<int> bytes, String algo) {
    switch (algo) {
      case 'sha1':
        return sha1.convert(bytes);
      case 'md5':
        return md5.convert(bytes);
      default:
        return sha256.convert(bytes);
    }
  }
}
