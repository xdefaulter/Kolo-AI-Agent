import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/bootstrap/bootstrap_utils.dart';

void main() {
  group('bootstrapArchForAbi', () {
    test('maps Android ABI names to Termux bootstrap archive names', () {
      expect(bootstrapArchForAbi('arm64-v8a'), 'aarch64');
      expect(bootstrapArchForAbi('armeabi-v7a'), 'arm');
      expect(bootstrapArchForAbi('x86_64'), 'x86_64');
      expect(bootstrapArchForAbi('x86'), 'i686');
    });

    test('defaults unknown or blank ABI values to aarch64', () {
      expect(bootstrapArchForAbi(''), 'aarch64');
      expect(bootstrapArchForAbi(' riscv64 '), 'aarch64');
    });
  });

  group('byte helpers', () {
    test('relocatable binary prefix preserves Termux prefix byte length', () {
      expect(
        utf8.encode(relocatableBootstrapPrefix).length,
        utf8.encode(termuxBootstrapPrefix).length,
      );
      expect(
        utf8.encode(relocatableBootstrapHome).length,
        utf8.encode(termuxBootstrapHome).length,
      );
      expect(
        utf8.encode(relocatableBootstrapAptCache).length,
        utf8.encode(termuxBootstrapAptCache).length,
      );
    });

    test('containsBytes finds a byte sequence anywhere in content', () {
      final content = utf8.encode('abc/data/data/com.termux/files/usr/bin/sh');
      final needle = utf8.encode(termuxBootstrapPrefix);

      expect(containsBytes(content, needle), isTrue);
      expect(containsBytes(content, utf8.encode('/missing')), isFalse);
      expect(containsBytes(content, const []), isFalse);
    });

    test('replaceBytes replaces every non-overlapping occurrence', () {
      final content = utf8.encode('aa-termux-aa-termux-aa');
      final result = replaceBytes(
        content,
        utf8.encode('termux'),
        utf8.encode('kolo'),
      );

      expect(utf8.decode(result), 'aa-kolo-aa-kolo-aa');
    });

    test('replaceBytes preserves binary content without a match', () {
      final content = [0, 1, 2, 3, 255];

      expect(replaceBytes(content, [9], [8]), content);
    });

    test('rewriteTermuxPrefix expands text files to the app prefix', () {
      final content = utf8.encode(
        '#!$termuxBootstrapPrefix/bin/sh\n'
        'cache=$termuxBootstrapAptCache\n'
        'home=$termuxBootstrapHome\n',
      );
      final result = rewriteTermuxPrefix(
        content,
        '/data/user/0/com.kolo.kolo_ai_agent/files/usr',
      );

      expect(
        utf8.decode(result),
        '#!/data/user/0/com.kolo.kolo_ai_agent/files/usr/bin/sh\n'
        'cache=/data/user/0/com.kolo.kolo_ai_agent/files/usr/var/cache/apt\n'
        'home=/data/user/0/com.kolo.kolo_ai_agent/files/usr/home\n',
      );
    });

    test(
      'rewriteTermuxPrefix relocates binary files without changing size',
      () {
        final content = [
          0,
          ...utf8.encode(
            '$termuxBootstrapPrefix/etc/dpkg\n'
            '$termuxBootstrapAptCache/archives\n'
            '$termuxBootstrapHome/.bashrc',
          ),
          255,
        ];
        final result = rewriteTermuxPrefix(
          content,
          '/data/user/0/com.kolo.kolo_ai_agent/files/usr',
        );

        expect(result.length, content.length);
        expect(
          utf8.decode(result.sublist(1, result.length - 1)),
          '$relocatableBootstrapPrefix/etc/dpkg\n'
          '$relocatableBootstrapAptCache/archives\n'
          '$relocatableBootstrapHome/.bashrc',
        );
      },
    );
  });
}
