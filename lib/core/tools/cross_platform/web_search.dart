import 'dart:convert';

import 'package:dio/dio.dart';

import '../tool_base.dart';
import '../../api/shared_dio.dart';
import '../../search_settings.dart';
import '../../storage/database.dart';
import 'web_cache.dart';

/// Web search tool.
///
/// Strategy:
///  1. User can pick a provider in Settings (stored under `search_provider`).
///  2. If the provider needs a key and none is configured, we fall through to
///     the next available option in this order:
///         Jina AI (no key needed) → Brave → Serper → Tavily → DuckDuckGo HTML
///  3. Jina is the default because it works without signup and returns
///     LLM-friendly markdown.
class WebSearchTool extends KoloTool {
  Dio get _dio => SharedDio.instance;

  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Search the web. Returns top results with titles, URLs, and snippets. '
      'Backed by Jina AI by default; Brave / Serper / Tavily can be configured in Settings.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Search query'},
      'count': {
        'type': 'integer',
        'description': 'Number of results to return (default 8, max 15)',
      },
    },
    'required': ['query'],
    'additionalProperties': false,
  };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> params,
    ToolContext context,
  ) async {
    final query = (params['query'] as String).trim();
    if (query.isEmpty) return ToolResult.err('Empty query');
    final maxResults = ((params['count'] as int?) ?? 8).clamp(1, 15);

    final cacheKey = 'search:$query:$maxResults';
    final cached = WebCache.instance.get(cacheKey);
    if (cached != null) return ToolResult.ok(cached);

    final configured = await _resolveProvider();

    // Try the configured provider first, then fall back through the chain.
    final attempts = _providerChain(configured);
    Object? lastError;
    for (final provider in attempts) {
      try {
        final result = await _runProvider(provider, query, maxResults);
        if (result != null && result.isNotEmpty) {
          WebCache.instance.put(cacheKey, result);
          return ToolResult.ok(
            result,
            metadata: {'query': query, 'provider': provider.name},
          );
        }
      } catch (e) {
        lastError = e;
        // continue to next provider
      }
    }
    return ToolResult.err(
      'Search failed across all providers${lastError != null ? ': $lastError' : ''}',
    );
  }

  Future<SearchProvider> _resolveProvider() async {
    final raw = await AppDatabase.instance.getSetting(kSearchProviderKey);
    return SearchProvider.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => SearchProvider.jina,
    );
  }

  /// Return the provider we try first, then reasonable fallbacks.
  List<SearchProvider> _providerChain(SearchProvider first) {
    final rest = [
      SearchProvider.jina,
      SearchProvider.brave,
      SearchProvider.serper,
      SearchProvider.tavily,
      SearchProvider.duckduckgo,
    ]..removeWhere((p) => p == first);
    return [first, ...rest];
  }

  Future<String?> _runProvider(SearchProvider p, String query, int maxResults) {
    switch (p) {
      case SearchProvider.jina:
        return _searchJina(query, maxResults);
      case SearchProvider.brave:
        return _searchBrave(query, maxResults);
      case SearchProvider.serper:
        return _searchSerper(query, maxResults);
      case SearchProvider.tavily:
        return _searchTavily(query, maxResults);
      case SearchProvider.duckduckgo:
        return _searchDuckDuckGo(query, maxResults);
    }
  }

  // ── Jina AI (default; no key required) ────────────────────────────────

  Future<String?> _searchJina(String query, int maxResults) async {
    // `s.jina.ai` returns LLM-friendly markdown directly. No API key needed
    // for the public endpoint — key only raises rate limits.
    final apiKey = await AppDatabase.instance.getSetting(kSearchJinaKey);
    final response = await _dio.get<dynamic>(
      'https://s.jina.ai/${Uri.encodeComponent(query)}',
      options: Options(
        headers: {
          'Accept': 'application/json',
          'X-Return-Format': 'markdown',
          if (apiKey != null && apiKey.isNotEmpty)
            'Authorization': 'Bearer $apiKey',
        },
        responseType: ResponseType.plain,
      ),
    );
    if (response.statusCode != 200 || response.data == null) return null;

    // Jina returns either JSON (with Accept: application/json) or markdown
    // (without). We request JSON for reliable parsing.
    try {
      final raw = response.data;
      final parsed = raw is String ? jsonDecode(raw) : raw;
      if (parsed is Map && parsed['data'] is List) {
        final items = (parsed['data'] as List).take(maxResults);
        if (items.isEmpty) return null;
        return items
            .toList()
            .asMap()
            .entries
            .map((e) {
              final item = e.value as Map;
              final title = item['title']?.toString() ?? '';
              final url = item['url']?.toString() ?? '';
              final desc =
                  item['description']?.toString() ??
                  item['snippet']?.toString() ??
                  item['content']?.toString() ??
                  '';
              return '${e.key + 1}. $title\n   $url\n   ${_truncate(desc, 400)}';
            })
            .join('\n\n');
      }
    } catch (_) {
      // Fall through — treat response as markdown text.
    }
    // Return the markdown as-is; Jina's format is already LLM-readable.
    final text = response.data.toString();
    if (text.trim().isEmpty) return null;
    return _truncate(text, 6000);
  }

  // ── Brave Search API ──────────────────────────────────────────────────

  Future<String?> _searchBrave(String query, int maxResults) async {
    final key = await AppDatabase.instance.getSetting(kSearchBraveKey);
    if (key == null || key.isEmpty) return null;

    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.search.brave.com/res/v1/web/search',
      queryParameters: {'q': query, 'count': maxResults},
      options: Options(
        headers: {'Accept': 'application/json', 'X-Subscription-Token': key},
      ),
    );
    if (response.statusCode != 200) return null;
    final web = response.data?['web'];
    final results = web is Map ? web['results'] as List? : null;
    if (results == null || results.isEmpty) return null;
    return results
        .take(maxResults)
        .toList()
        .asMap()
        .entries
        .map((e) {
          final r = e.value as Map;
          return '${e.key + 1}. ${r['title']}\n   ${r['url']}\n   ${_truncate(r['description']?.toString() ?? '', 400)}';
        })
        .join('\n\n');
  }

  // ── Serper.dev (Google wrapper) ───────────────────────────────────────

  Future<String?> _searchSerper(String query, int maxResults) async {
    final key = await AppDatabase.instance.getSetting(kSearchSerperKey);
    if (key == null || key.isEmpty) return null;

    final response = await _dio.post<Map<String, dynamic>>(
      'https://google.serper.dev/search',
      data: {'q': query, 'num': maxResults},
      options: Options(
        headers: {'X-API-KEY': key, 'Content-Type': 'application/json'},
      ),
    );
    if (response.statusCode != 200) return null;
    final organic = response.data?['organic'] as List?;
    if (organic == null || organic.isEmpty) return null;
    return organic
        .take(maxResults)
        .toList()
        .asMap()
        .entries
        .map((e) {
          final r = e.value as Map;
          return '${e.key + 1}. ${r['title']}\n   ${r['link']}\n   ${_truncate(r['snippet']?.toString() ?? '', 400)}';
        })
        .join('\n\n');
  }

  // ── Tavily (LLM-optimized) ────────────────────────────────────────────

  Future<String?> _searchTavily(String query, int maxResults) async {
    final key = await AppDatabase.instance.getSetting(kSearchTavilyKey);
    if (key == null || key.isEmpty) return null;

    final response = await _dio.post<Map<String, dynamic>>(
      'https://api.tavily.com/search',
      data: {
        'api_key': key,
        'query': query,
        'max_results': maxResults,
        'include_answer': false,
        'search_depth': 'basic',
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    if (response.statusCode != 200) return null;
    final items = response.data?['results'] as List?;
    if (items == null || items.isEmpty) return null;
    return items
        .take(maxResults)
        .toList()
        .asMap()
        .entries
        .map((e) {
          final r = e.value as Map;
          return '${e.key + 1}. ${r['title']}\n   ${r['url']}\n   ${_truncate(r['content']?.toString() ?? '', 400)}';
        })
        .join('\n\n');
  }

  // ── DuckDuckGo HTML (last-resort fallback) ────────────────────────────

  Future<String?> _searchDuckDuckGo(String query, int maxResults) async {
    final response = await _dio.get<dynamic>(
      'https://lite.duckduckgo.com/lite/',
      queryParameters: {'q': query, 'kl': 'wt-wt'},
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        responseType: ResponseType.plain,
      ),
    );
    if (response.statusCode != 200) return null;
    final html = response.data as String;
    final results = _parseDuckDuckGoLite(html, maxResults);
    if (results.isEmpty) return null;
    return results
        .asMap()
        .entries
        .map((e) {
          return '${e.key + 1}. ${e.value['title']}\n   ${e.value['url']}\n   ${e.value['snippet']}';
        })
        .join('\n\n');
  }

  // Hot-path patterns: previously these were rebuilt on every search
  // call (and `_uddgRe` was rebuilt _per result link_ in the loop). Each
  // RegExp construction parses + compiles an automaton — moving them to
  // statics drops 3 RegExp allocations per query plus one extra per
  // matching result, which dominated the parser's cost on warm caches.
  static final _linkRe = RegExp(
    r'<a[^>]*class="result-link"[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
    multiLine: true,
  );
  static final _snippetRe = RegExp(
    r'<td[^>]*class="result-snippet"[^>]*>(.*?)</td>',
    multiLine: true,
  );
  static final _uddgRe = RegExp(r'uddg=([^&]+)');

  List<Map<String, String>> _parseDuckDuckGoLite(String html, int maxResults) {
    final results = <Map<String, String>>[];
    // Snippets are pulled by index; we still need a List for `[i]` access.
    // Links can stream — iterate once and break early when we hit
    // `maxResults` instead of materialising the whole match list. On
    // pages with hundreds of links this saves the trailing N-maxResults
    // Match objects.
    final snippets = _snippetRe.allMatches(html).toList(growable: false);
    int i = 0;
    for (final linkMatch in _linkRe.allMatches(html)) {
      if (results.length >= maxResults) break;
      final url = _decodeHtml(linkMatch.group(1) ?? '');
      final title = _decodeHtml(linkMatch.group(2) ?? '');
      if (url.isEmpty || url.contains('duckduckgo.com') || title.isEmpty) {
        i++;
        continue;
      }
      String cleanUrl = url;
      if (url.contains('uddg=')) {
        final uddgMatch = _uddgRe.firstMatch(url);
        if (uddgMatch != null) {
          cleanUrl = Uri.decodeComponent(uddgMatch.group(1) ?? url);
        }
      }
      final snippet = i < snippets.length
          ? _decodeHtml(snippets[i].group(1) ?? '')
          : '';
      results.add({'title': title, 'url': cleanUrl, 'snippet': snippet});
      i++;
    }
    return results;
  }

  // Single regex matches every entity we care about + any HTML tag, so
  // _decodeHtml does one O(n) pass instead of seven sequential
  // replaceAll calls (six entities + tag strip). Hot when the
  // DuckDuckGo fallback parses ~15 result snippets per query.
  static final _htmlEntityOrTagRe =
      RegExp(r'<[^>]*>|&(?:amp|lt|gt|quot|#39|apos);');
  static const Map<String, String> _entityMap = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
  };

  String _decodeHtml(String s) {
    if (s.isEmpty) return s;
    final out = s.replaceAllMapped(_htmlEntityOrTagRe, (m) {
      final src = m.group(0)!;
      if (src.startsWith('<')) return '';
      return _entityMap[src] ?? src;
    });
    return out.trim();
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';
}
