import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/tools/custom_tool_def.dart';
import 'package:kolo_ai_agent/core/tools/tool_base.dart';

void main() {
  group('CustomToolDef JSON roundtrip', () {
    test('shell kind preserves all fields including timestamps', () {
      final t = CustomToolDef(
        id: 'abc',
        name: 'resize_image',
        description: 'resize images via imagemagick',
        parameterSchema: const {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'width': {'type': 'integer'},
          },
          'required': ['path', 'width'],
        },
        permission: ToolPermission.dangerous,
        kind: CustomToolKind.shell,
        implementation: const {
          'command': 'convert {{path}} -resize {{width}}x {{path}}',
          'timeoutSec': 30,
        },
        createdAt: DateTime.utc(2026, 4, 23, 10),
        updatedAt: DateTime.utc(2026, 4, 23, 11),
      );
      final round = CustomToolDef.fromMap(t.toMap());
      expect(round.id, 'abc');
      expect(round.name, 'resize_image');
      expect(round.description, 'resize images via imagemagick');
      expect(round.permission, ToolPermission.dangerous);
      expect(round.kind, CustomToolKind.shell);
      expect(round.implementation['command'], contains('convert'));
      expect(round.implementation['timeoutSec'], 30);
      expect(round.parameterSchema['required'], contains('path'));
      expect(round.createdAt, DateTime.utc(2026, 4, 23, 10));
      expect(round.updatedAt, DateTime.utc(2026, 4, 23, 11));
    });

    test('unknown permission falls back to dangerous (fail closed)', () {
      final raw = {
        'id': 'x',
        'name': 'x',
        'description': 'x' * 20,
        'parameterSchema': {'type': 'object', 'properties': {}},
        'permission': 'nonsense',
        'kind': 'shell',
        'implementation': {'command': 'ls'},
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      final t = CustomToolDef.fromMap(raw);
      expect(t.permission, ToolPermission.dangerous);
    });

    test('copyWith refreshes updatedAt but preserves createdAt', () async {
      final original = CustomToolDef(
        id: 'a',
        name: 'n',
        description: 'desc that is long enough',
        parameterSchema: const {'type': 'object', 'properties': {}},
        permission: ToolPermission.safe,
        kind: CustomToolKind.shell,
        implementation: const {'command': 'ls'},
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final edited = original.copyWith(description: 'updated description here');
      expect(edited.createdAt, original.createdAt);
      expect(edited.updatedAt.isAfter(original.updatedAt), isTrue);
      expect(edited.description, 'updated description here');
    });
  });

  group('renderTemplate — injection safety + substitution', () {
    test('substitutes placeholders with quoted values', () {
      final out = renderTemplate('echo {{msg}}', {'msg': 'hello world'});
      expect(out, "echo 'hello world'");
    });

    test('strips shell metacharacters from values before substitution', () {
      // Even if the *value* contains `;` or `$()`, it gets stripped before
      // being wrapped in the single-quoted substitution. Template structure
      // is author-trusted but values are not.
      final out = renderTemplate('echo {{msg}}', {'msg': 'hi; rm -rf /'});
      // The semicolon + rm survive as plain chars inside single quotes, but
      // `;` is in our strip-set so it's removed. Result: `echo 'hi rm -rf '`
      expect(out, contains("'"));
      expect(out, isNot(contains(';'))); // stripped
      expect(out, startsWith('echo '));
    });

    test('strips single quotes from values entirely (safer than escape)', () {
      // Our allow-char regex doesn't include single quote, so "it's a test"
      // becomes "its a test" inside the quoted substitution. That's SAFER
      // than close-escape-reopen — the value can't break out of its
      // quoted context because there's no quote to escape from.
      final out = renderTemplate('echo {{q}}', {'q': "it's a test"});
      expect(out, "echo 'its a test'");
    });

    test('JSON-encodes non-string values', () {
      final out = renderTemplate('count={{n}}', {'n': 42});
      expect(out, "count='42'");
    });

    test('throws on missing placeholder arg', () {
      expect(
        () => renderTemplate('echo {{missing}}', const {}),
        throwsA(isA<TemplateRenderError>()),
      );
    });

    test('fast path: template with no placeholders is returned unchanged', () {
      const t = 'echo static command';
      expect(renderTemplate(t, const {}), t);
    });

    test('unterminated placeholder is emitted literally (not thrown)', () {
      final out = renderTemplate('echo {{broken', const {});
      expect(out, 'echo {{broken');
    });

    test('strips newlines from values (no multi-line shell injection)', () {
      // Newlines are stripped so a malicious value can't inject a new
      // command line. Note: `rm -rf` substring may appear INSIDE the
      // single-quotes but that's inert — POSIX single-quotes suppress all
      // shell interpretation, so even `rm -rf` between `'` marks is just
      // literal text echoed back.
      final out = renderTemplate('echo {{x}}', {'x': 'line1\nrm -rf /\nline2'});
      expect(out, isNot(contains('\n')));
      // All characters between the single quotes are rendered literally;
      // nothing escapes the quoted context.
      expect(out, startsWith("echo '"));
      expect(out, endsWith("'"));
    });

    test('backticks and \$ are stripped (command substitution blocked)', () {
      final out = renderTemplate('echo {{x}}', {'x': r'safe`$(rm -rf /)`more'});
      expect(out, isNot(contains('`')));
      expect(out, isNot(contains(r'$(')));
    });
  });

  group('CustomToolKind wire name', () {
    test('round-trips through parse', () {
      for (final k in CustomToolKind.values) {
        expect(CustomToolKindX.parse(k.wireName), k);
      }
    });

    test('parse returns null on unknown', () {
      expect(CustomToolKindX.parse('nonsense'), isNull);
      expect(CustomToolKindX.parse(null), isNull);
    });
  });

  group('renderPlainTemplate — prompt/composed substitution', () {
    test('inserts the raw value (no shell quoting)', () {
      final out = renderPlainTemplate('You are {{role}}', {'role': 'poet'});
      expect(out, 'You are poet');
    });

    test('allows punctuation that shell rendering would strip', () {
      // Unlike shell rendering, plain templates preserve quotes, ampersands,
      // etc. — the output goes to an LLM or another tool's arg map, not a
      // shell, so those chars are inert.
      final out = renderPlainTemplate('Summarize: "{{input}}"', {
        'input': "Q&A session; with 'quotes' & stuff!",
      });
      expect(out, contains('&'));
      expect(out, contains("'quotes'"));
      expect(out, contains(';'));
    });

    test(
      'strips template delimiters from values (no second-pass injection)',
      () {
        // A malicious value that contains `{{other}}` should NOT cause a
        // second substitution pass. We strip `{{` and `}}` from values.
        final out = renderPlainTemplate('Hello {{x}}', {
          'x': 'evil {{inject}} user',
        });
        expect(out, 'Hello evil inject user');
        expect(out, isNot(contains('{{')));
        expect(out, isNot(contains('}}')));
      },
    );

    test('JSON-encodes non-string values', () {
      final out = renderPlainTemplate('count: {{n}}, items: {{xs}}', {
        'n': 3,
        'xs': [1, 2, 3],
      });
      expect(out, 'count: 3, items: [1,2,3]');
    });

    test('throws TemplateRenderError on missing arg', () {
      expect(
        () => renderPlainTemplate('{{missing}}', const {}),
        throwsA(isA<TemplateRenderError>()),
      );
    });

    test('fast path: no placeholders returns unchanged', () {
      expect(renderPlainTemplate('plain', const {}), 'plain');
    });

    test('unterminated placeholder emitted literally, not thrown', () {
      expect(renderPlainTemplate('x {{open', const {}), 'x {{open');
    });
  });
}
