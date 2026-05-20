import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage/database.dart';

/// Supported web-search backends.
enum SearchProvider {
  /// Default. No API key required; works out of the box. Returns
  /// LLM-friendly markdown via s.jina.ai.
  jina,

  /// Brave Search API. 2000 free queries/month. Requires API key.
  brave,

  /// Serper.dev — Google results wrapper. Requires API key.
  serper,

  /// Tavily — purpose-built for LLM search. Requires API key.
  tavily,

  /// Last-resort fallback. Scrapes lite.duckduckgo.com (often blocks).
  duckduckgo,
}

extension SearchProviderUi on SearchProvider {
  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case SearchProvider.jina:
        return 'Jina AI (default, no key)';
      case SearchProvider.brave:
        return 'Brave Search';
      case SearchProvider.serper:
        return 'Serper (Google)';
      case SearchProvider.tavily:
        return 'Tavily';
      case SearchProvider.duckduckgo:
        return 'DuckDuckGo (fallback)';
    }
  }

  /// One-liner explaining the trade-off.
  String get description {
    switch (this) {
      case SearchProvider.jina:
        return 'Free, no signup. Rate limited. Optional API key lifts the limit.';
      case SearchProvider.brave:
        return '2000 free queries/month. Best quality privacy-respecting results.';
      case SearchProvider.serper:
        return 'Real Google results. 2500 signup credits, then paid.';
      case SearchProvider.tavily:
        return 'LLM-optimized answers. 1000 free/month.';
      case SearchProvider.duckduckgo:
        return 'Scrapes lite.duckduckgo.com. Frequently blocked, use only as fallback.';
    }
  }

  /// Whether this provider needs an API key to function.
  /// Jina still works without a key — the key only lifts rate limits.
  bool get requiresKey {
    switch (this) {
      case SearchProvider.brave:
      case SearchProvider.serper:
      case SearchProvider.tavily:
        return true;
      case SearchProvider.jina:
      case SearchProvider.duckduckgo:
        return false;
    }
  }

  /// Settings key for this provider's API key, or null if none is used.
  String? get apiKeySettingKey {
    switch (this) {
      case SearchProvider.jina:
        return kSearchJinaKey;
      case SearchProvider.brave:
        return kSearchBraveKey;
      case SearchProvider.serper:
        return kSearchSerperKey;
      case SearchProvider.tavily:
        return kSearchTavilyKey;
      case SearchProvider.duckduckgo:
        return null;
    }
  }
}

// Setting keys (persisted in AppDatabase). Kept public so WebSearchTool and
// the Settings screen refer to the same strings.
const String kSearchProviderKey = 'search_provider';
const String kSearchJinaKey = 'jina_api_key';
const String kSearchBraveKey = 'brave_api_key';
const String kSearchSerperKey = 'serper_api_key';
const String kSearchTavilyKey = 'tavily_api_key';

/// Riverpod notifier for the user's chosen search backend. The provider is
/// persisted in [AppDatabase] under [kSearchProviderKey] and loaded on first
/// read.
class SearchProviderNotifier extends StateNotifier<SearchProvider> {
  SearchProviderNotifier() : super(SearchProvider.jina) {
    _load();
  }

  Future<void> _load() async {
    final raw = await AppDatabase.instance.getSetting(kSearchProviderKey);
    if (raw != null && raw.isNotEmpty) {
      state = SearchProvider.values.firstWhere(
        (p) => p.name == raw,
        orElse: () => SearchProvider.jina,
      );
    }
  }

  Future<void> set(SearchProvider p) async {
    state = p;
    await AppDatabase.instance.saveSetting(kSearchProviderKey, p.name);
  }
}

final searchProviderConfigProvider =
    StateNotifierProvider<SearchProviderNotifier, SearchProvider>(
      (ref) => SearchProviderNotifier(),
    );
