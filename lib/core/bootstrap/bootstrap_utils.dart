import 'dart:convert';
import 'dart:typed_data';

const termuxAppDataPrefix = '/data/data/com.termux';
const termuxBootstrapPrefix = '/data/data/com.termux/files/usr';
const termuxBootstrapHome = '/data/data/com.termux/files/home';
const termuxBootstrapAptCache = '/data/data/com.termux/cache/apt';

// Same byte length as [termuxBootstrapPrefix], so it is safe to patch into
// ELF string constants. Bootstrap tools must be launched with cwd set to the
// app's files directory, where `usr` is the extracted prefix.
const relocatableBootstrapPrefix = '/proc/self/cwd/usr/././././././';
const relocatableBootstrapHome = '/proc/self/cwd/usr/home/././././';
const relocatableBootstrapAptCache = '/proc/self/cwd/usr/var/c/apt/./';

final _termuxAppDataPrefixBytes = utf8.encode(termuxAppDataPrefix);
final _termuxBootstrapPrefixBytes = utf8.encode(termuxBootstrapPrefix);
final _termuxBootstrapHomeBytes = utf8.encode(termuxBootstrapHome);
final _termuxBootstrapAptCacheBytes = utf8.encode(termuxBootstrapAptCache);

String bootstrapArchForAbi(String abi) {
  final normalized = abi.trim();
  if (normalized.startsWith('arm64')) return 'aarch64';
  if (normalized.startsWith('armeabi')) return 'arm';
  if (normalized.startsWith('x86_64')) return 'x86_64';
  if (normalized.startsWith('x86')) return 'i686';
  return 'aarch64';
}

bool containsBytes(List<int> content, List<int> needle) {
  final needleLength = needle.length;
  final contentLength = content.length;
  if (needleLength == 0 || contentLength < needleLength) return false;

  final firstByte = needle[0];
  outer:
  for (var i = 0; i <= contentLength - needleLength; i++) {
    if (content[i] != firstByte) continue;
    for (var j = 1; j < needleLength; j++) {
      if (content[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

bool isLikelyBinary(List<int> content) {
  final scanLength = content.length < 4096 ? content.length : 4096;
  for (var i = 0; i < scanLength; i++) {
    if (content[i] == 0) return true;
  }
  return false;
}

List<int> rewriteTermuxPrefix(List<int> content, String actualPrefix) {
  if (!containsBytes(content, _termuxAppDataPrefixBytes)) {
    return content;
  }

  final binary = isLikelyBinary(content);
  final replacements = <(List<int>, String)>[
    (
      _termuxBootstrapPrefixBytes,
      binary ? relocatableBootstrapPrefix : actualPrefix,
    ),
    (
      _termuxBootstrapHomeBytes,
      binary ? relocatableBootstrapHome : '$actualPrefix/home',
    ),
    (
      _termuxBootstrapAptCacheBytes,
      binary ? relocatableBootstrapAptCache : '$actualPrefix/var/cache/apt',
    ),
  ];

  var result = content;
  for (final (from, toString) in replacements) {
    if (!containsBytes(result, from)) continue;

    final to = utf8.encode(toString);
    if (binary && to.length != from.length) {
      throw StateError(
        'Binary bootstrap prefix replacement must preserve byte length.',
      );
    }
    result = replaceBytes(result, from, to);
  }
  return result;
}

List<int> replaceBytes(List<int> content, List<int> from, List<int> to) {
  if (from.isEmpty) return List<int>.from(content);

  final out = BytesBuilder(copy: false);
  final fromLength = from.length;
  final contentLength = content.length;
  var i = 0;

  while (i < contentLength) {
    if (i <= contentLength - fromLength && content[i] == from[0]) {
      var match = true;
      for (var j = 1; j < fromLength; j++) {
        if (content[i + j] != from[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        out.add(to);
        i += fromLength;
        continue;
      }
    }
    out.addByte(content[i]);
    i++;
  }

  return out.toBytes();
}
