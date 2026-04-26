import 'package:dio/dio.dart';
import '../tool_base.dart';
import '../../api/shared_dio.dart';
import 'web_cache.dart';

// Hot-path regexes hoisted to module-level so each scrape doesn't
// recompile half a dozen patterns. Compiling a RegExp in Dart isn't
// free — it parses the pattern + builds an automaton — and these were
// being constructed on every call to _htmlToText / _decodeEntities /
// _sanitizeForLlm / _extractTitle. With a popular site that's ~6 fresh
// allocations per scrape; cached, it's zero.
final RegExp _kTitleRe = RegExp(
  r'<title[^>]*>(.*?)</title>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _kStripBlockRe = RegExp(
  r'<(script|style|svg|head|noscript)[^>]*>.*?</\1>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _kAnyTagRe = RegExp(r'<[^>]+>');
final RegExp _kCollapseHorizWsRe = RegExp(r'[ \t]+');
final RegExp _kCollapseBlankLinesRe = RegExp(r'\n{3,}');
final RegExp _kPromptInjectionRe = RegExp(
  r'(ignore|disregard|forget)\s+(all\s+)?(previous|prior|above)\s+(instructions|prompts|context)',
  caseSensitive: false,
);
final RegExp _kNumericEntityRe = RegExp(r'&#(\d+);');

/// Fetch a URL and extract clean readable text, stripping HTML/JS/CSS noise.
class WebScrapeTool extends KoloTool {
  Dio get _dio => SharedDio.instance;

  @override
  String get name => 'web_scrape';
  @override
  String get description => 'Fetch a web page and extract its readable text content, stripping HTML tags, scripts, and styles. Returns clean text with title.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL to scrape'},
      'max_length': {'type': 'integer', 'description': 'Maximum characters to return (default 8000)'},
    },
    'required': ['url'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final url = params['url'] as String;
    final maxLength = params['max_length'] as int? ?? 8000;

    // Check cache first
    final cacheKey = 'scrape:$url';
    final cached = WebCache.instance.get(cacheKey);
    if (cached != null) return ToolResult.ok(cached);

    try {
      final response = await _dio.get<String>(url, options: Options(
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 400,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ));
      final html = response.data ?? '';
      final title = _extractTitle(html);
      final text = _htmlToText(html);
      final result = StringBuffer();
      if (title.isNotEmpty) result.writeln('Title: $title');
      result.writeln('URL: $url');
      result.writeln('---');
      var cleanText = text.trim();
      if (cleanText.length > maxLength) {
        cleanText = '${cleanText.substring(0, maxLength)}... [truncated]';
      }
      // Sanitize: strip common prompt injection patterns
      cleanText = _sanitizeForLlm(cleanText);
      result.write(cleanText);
      final output = result.toString();
      WebCache.instance.put(cacheKey, output);
      return ToolResult.ok(output);
    } catch (e) {
      return ToolResult.err('Scrape failed: $e');
    }
  }

  String _extractTitle(String html) {
    final match = _kTitleRe.firstMatch(html);
    return match != null ? _decodeEntities(match.group(1)?.trim() ?? '') : '';
  }

  String _htmlToText(String html) {
    var text = html;
    text = text.replaceAll(_kStripBlockRe, '');
    text = text.replaceAll(_kAnyTagRe, ' ');
    text = _decodeEntities(text);
    text = text.replaceAll(_kCollapseHorizWsRe, ' ');
    text = text.replaceAll(_kCollapseBlankLinesRe, '\n\n');
    return text.trim();
  }

  /// Strip common prompt injection patterns from scraped content
  String _sanitizeForLlm(String text) {
    return text.replaceAll(_kPromptInjectionRe, '[content filtered]');
  }

  String _decodeEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(_kNumericEntityRe, (Match m) {
          final code = int.tryParse(m.group(1) ?? '');
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        });
  }
}