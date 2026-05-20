import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/search_settings.dart';

void main() {
  group('SearchProvider enum', () {
    test('default set is exhaustive', () {
      expect(SearchProvider.values.map((e) => e.name).toSet(), {
        'jina',
        'brave',
        'serper',
        'tavily',
        'duckduckgo',
      });
    });

    test('jina is first — it is our zero-config default', () {
      expect(SearchProvider.values.first, SearchProvider.jina);
    });
  });

  group('SearchProviderUi.requiresKey', () {
    test('jina and duckduckgo do not require a key', () {
      expect(SearchProvider.jina.requiresKey, isFalse);
      expect(SearchProvider.duckduckgo.requiresKey, isFalse);
    });

    test('brave, serper, tavily require a key', () {
      expect(SearchProvider.brave.requiresKey, isTrue);
      expect(SearchProvider.serper.requiresKey, isTrue);
      expect(SearchProvider.tavily.requiresKey, isTrue);
    });
  });

  group('SearchProviderUi.apiKeySettingKey', () {
    test('duckduckgo has no key storage', () {
      expect(SearchProvider.duckduckgo.apiKeySettingKey, isNull);
    });

    test('every other provider maps to a unique key', () {
      final keys = <String>{};
      for (final p in SearchProvider.values) {
        final k = p.apiKeySettingKey;
        if (k != null) keys.add(k);
      }
      expect(keys, {
        kSearchJinaKey,
        kSearchBraveKey,
        kSearchSerperKey,
        kSearchTavilyKey,
      });
    });

    test('all setting key constants are non-empty strings', () {
      for (final k in [
        kSearchProviderKey,
        kSearchJinaKey,
        kSearchBraveKey,
        kSearchSerperKey,
        kSearchTavilyKey,
      ]) {
        expect(k, isNotEmpty);
      }
    });
  });

  group('SearchProviderUi.label / description', () {
    test('every provider has a non-empty label', () {
      for (final p in SearchProvider.values) {
        expect(p.label, isNotEmpty, reason: '${p.name} missing label');
      }
    });

    test('every provider has a non-empty description', () {
      for (final p in SearchProvider.values) {
        expect(
          p.description,
          isNotEmpty,
          reason: '${p.name} missing description',
        );
      }
    });

    test('labels are unique', () {
      final labels = SearchProvider.values.map((p) => p.label).toList();
      expect(labels.toSet().length, labels.length);
    });
  });
}
