import 'dart:collection';

/// Simple in-memory LRU cache for web requests to avoid redundant network calls.
class WebCache {
  static final WebCache instance = WebCache._();
  WebCache._();

  static const _maxEntries = 50;
  static const _ttl = Duration(minutes: 10);

  final _cache = LinkedHashMap<String, _CacheEntry>();

  String? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > _ttl) {
      _cache.remove(key);
      return null;
    }
    // Move to end (most recently used)
    _cache.remove(key);
    _cache[key] = entry;
    return entry.value;
  }

  void put(String key, String value) {
    _cache.remove(key);
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(value: value, timestamp: DateTime.now());
  }
}

class _CacheEntry {
  final String value;
  final DateTime timestamp;
  _CacheEntry({required this.value, required this.timestamp});
}
