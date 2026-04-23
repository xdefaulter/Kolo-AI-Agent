import 'package:dio/dio.dart';
import '../tool_base.dart';
import '../../api/shared_dio.dart';
import 'web_cache.dart';

/// Web search using DuckDuckGo HTML search (lite.duckduckgo.com).
/// The old api.duckduckgo.com/?format=json endpoint is the Instant Answer API
/// which returns almost nothing for most queries — this uses the HTML endpoint
/// and parses the actual search results.
class WebSearchTool extends KoloTool {
  Dio get _dio => SharedDio.instance;

  @override String get name => 'web_search';
  @override String get description => 'Search the web using DuckDuckGo. Returns top results with titles, URLs, and snippets.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Search query'},
      'count': {'type': 'integer', 'description': 'Number of results to return (default 8, max 15)'},
    },
    'required': ['query'],
    'additionalProperties': false,
  };
  @override ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final query = params['query'] as String;
    final maxResults = ((params['count'] as int?) ?? 8).clamp(1, 15);

    final cacheKey = 'search:$query:$maxResults';
    final cached = WebCache.instance.get(cacheKey);
    if (cached != null) return ToolResult.ok(cached);

    try {
      // Use DuckDuckGo HTML lite endpoint which returns parseable search results
      final response = await _dio.get(
        'https://lite.duckduckgo.com/lite/',
        queryParameters: {'q': query, 'kl': 'wt-wt'},
        options: Options(headers: {
          'User-Agent': 'Mozilla/5.0 (Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        }),
      );

      if (response.statusCode != 200) {
        return ToolResult.err('Search returned HTTP ${response.statusCode}');
      }

      final html = response.data as String;
      final results = _parseDuckDuckGoLite(html, maxResults);

      if (results.isEmpty) {
        return ToolResult.ok('No results found for "$query". Try different keywords.');
      }

      final formatted = results.asMap().entries.map((e) =>
        '${e.key + 1}. ${e.value['title']}\n   ${e.value['url']}\n   ${e.value['snippet']}'
      ).join('\n\n');
      WebCache.instance.put(cacheKey, formatted);
      return ToolResult.ok(formatted, metadata: {
        'query': query,
        'resultCount': results.length,
      });
    } on FormatException {
      // 4.4: DuckDuckGo HTML format may have changed
      return ToolResult.err('Search parsing failed — DuckDuckGo HTML format may have changed. Try again later.');
    } catch (e) {
      return ToolResult.err('Search failed: $e');
    }
  }

  /// Parse DuckDuckGo Lite HTML page into structured results
  List<Map<String, String>> _parseDuckDuckGoLite(String html, int maxResults) {
    final results = <Map<String, String>>[];

    // DuckDuckGo Lite uses <a class="result-link"> for titles
    // and <td class="result-snippet"> for snippets
    // The HTML structure is simple tables

    // Try regex-based parsing for the lite format
    final linkPattern = RegExp(r'<a[^>]*class="result-link"[^>]*href="([^"]*)"[^>]*>(.*?)</a>', multiLine: true);
    final snippetPattern = RegExp(r'<td[^>]*class="result-snippet"[^>]*>(.*?)</td>', multiLine: true);

    final links = linkPattern.allMatches(html).toList();
    final snippets = snippetPattern.allMatches(html).toList();

    for (int i = 0; i < links.length && results.length < maxResults; i++) {
      final url = _decodeHtml(links[i].group(1) ?? '');
      final title = _decodeHtml(links[i].group(2) ?? '');

      // Skip ad results and empty urls
      if (url.isEmpty || url.contains('duckduckgo.com') || title.isEmpty) continue;
      // Skip DDG redirect URLs — extract actual URL
      String cleanUrl = url;
      if (url.contains('uddg=')) {
        final uddgMatch = RegExp(r'uddg=([^&]+)').firstMatch(url);
        if (uddgMatch != null) {
          cleanUrl = Uri.decodeComponent(uddgMatch.group(1) ?? url);
        }
      }

      String snippet = '';
      if (i < snippets.length) {
        snippet = _decodeHtml(snippets[i].group(1) ?? '');
      }

      results.add({'title': title, 'url': cleanUrl, 'snippet': snippet});
    }

    // Fallback: If the regex didn't find results, try a simpler pattern
    // (DDG HTML format can vary)
    if (results.isEmpty) {
      final simpleLinkPattern = RegExp(r'<a[^>]+href="(https?://[^"]+)"[^>]*>([^<]+)</a>', multiLine: true);
      for (final m in simpleLinkPattern.allMatches(html).take(maxResults)) {
        final url = m.group(1) ?? '';
        final title = _decodeHtml(m.group(2) ?? '');
        if (url.contains('duckduckgo.com') || title.isEmpty || title.contains('duckduckgo')) continue;
        results.add({'title': title, 'url': url, 'snippet': ''});
      }
    }

    return results;
  }

  /// Decode HTML entities
  String _decodeHtml(String s) {
    return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll(RegExp(r'<[^>]*>'), '') // strip remaining tags
      .trim();
  }
}