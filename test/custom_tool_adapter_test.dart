import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/tools/custom_tool_adapter.dart';
import 'package:kolo_ai_agent/core/tools/custom_tool_def.dart';
import 'package:kolo_ai_agent/core/tools/tool_base.dart';

/// A [ToolContext] the adapter tests can build without dragging in the
/// full agent session wiring. Defaults to auto-approve permissions and
/// nothing wired for the optional callbacks — individual tests override.
ToolContext _testContext({
  ToolSubLlmCall? subLlmCall,
  ToolRunByName? runToolByName,
}) {
  return ToolContext(
    chatId: 'test',
    permissionChecker: (_) async => true,
    subLlmCall: subLlmCall,
    runToolByName: runToolByName,
  );
}

CustomToolDef _promptDef({
  String systemPrompt = 'You are a test.',
  String userTemplate = 'Say: {{msg}}',
}) => CustomToolDef(
  id: 'p',
  name: 'test_prompt',
  description: 'test prompt-kind tool for adapter unit tests',
  parameterSchema: const {'type': 'object', 'properties': {}},
  permission: ToolPermission.safe,
  kind: CustomToolKind.prompt,
  implementation: {'systemPrompt': systemPrompt, 'userTemplate': userTemplate},
);

CustomToolDef _composedDef(List<Map<String, dynamic>> steps) => CustomToolDef(
  id: 'c',
  name: 'test_composed',
  description: 'test composed-kind tool for adapter unit tests',
  parameterSchema: const {'type': 'object', 'properties': {}},
  permission: ToolPermission.safe,
  kind: CustomToolKind.composed,
  implementation: {'steps': steps},
);

void main() {
  group('CustomToolAdapter — prompt kind', () {
    test('returns error when no subLlmCall is wired', () async {
      final adapter = CustomToolAdapter(_promptDef());
      final result = await adapter.execute(
        const {'msg': 'hello'},
        _testContext(), // no subLlmCall
      );
      expect(result.success, isFalse);
      expect(result.error, contains('LLM provider'));
    });

    test('renders userTemplate and passes systemPrompt through', () async {
      String? capturedSystem;
      String? capturedUser;
      Future<String> fakeCall({
        required String systemPrompt,
        required String userMessage,
      }) async {
        capturedSystem = systemPrompt;
        capturedUser = userMessage;
        return 'faked response';
      }

      final adapter = CustomToolAdapter(
        _promptDef(
          systemPrompt: 'You are a greeter.',
          userTemplate: 'Greet {{name}} in {{lang}}',
        ),
      );
      final result = await adapter.execute({
        'name': 'Ada',
        'lang': 'French',
      }, _testContext(subLlmCall: fakeCall));

      expect(result.success, isTrue);
      expect(result.output, 'faked response');
      expect(capturedSystem, 'You are a greeter.');
      expect(capturedUser, 'Greet Ada in French');
    });

    test('surfaces the sub-call error as a tool error', () async {
      Future<String> failing({
        required String systemPrompt,
        required String userMessage,
      }) async {
        throw StateError('network down');
      }

      final adapter = CustomToolAdapter(_promptDef());
      final result = await adapter.execute(const {
        'msg': 'x',
      }, _testContext(subLlmCall: failing));
      expect(result.success, isFalse);
      expect(result.error, contains('network down'));
    });
  });

  group('CustomToolAdapter — composed kind', () {
    test('runs each step in order and chains _previous output', () async {
      final calls = <(String, Map<String, dynamic>)>[];
      Future<ToolResult> fakeRun(String name, Map<String, dynamic> args) async {
        calls.add((name, Map.unmodifiable(args)));
        return ToolResult.ok('out-$name');
      }

      final adapter = CustomToolAdapter(
        _composedDef([
          {
            'tool': 'first',
            'args': {'in': '{{input}}'},
          },
          {
            'tool': 'second',
            // References the previous step's output via _previous.
            'args': {'in': '{{_previous}}-tail'},
          },
        ]),
      );
      final result = await adapter.execute({
        'input': 'start',
      }, _testContext(runToolByName: fakeRun));

      expect(result.success, isTrue);
      expect(calls.length, 2);
      expect(calls[0].$1, 'first');
      expect(calls[0].$2['in'], 'start');
      expect(calls[1].$1, 'second');
      expect(calls[1].$2['in'], 'out-first-tail');
      // Concatenated output preserves both steps.
      expect(result.output, contains('[step 0 first]'));
      expect(result.output, contains('[step 1 second]'));
    });

    test('aborts on first failing step with that step\'s error', () async {
      Future<ToolResult> fakeRun(String name, Map<String, dynamic> args) async {
        if (name == 'bad') return ToolResult.err('boom');
        return ToolResult.ok('ok-$name');
      }

      final adapter = CustomToolAdapter(
        _composedDef([
          {'tool': 'good', 'args': <String, dynamic>{}},
          {'tool': 'bad', 'args': <String, dynamic>{}},
          {'tool': 'never-reached', 'args': <String, dynamic>{}},
        ]),
      );
      final result = await adapter.execute(
        const {},
        _testContext(runToolByName: fakeRun),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('Step 1'));
      expect(result.error, contains('boom'));
    });

    test('preserves non-string args verbatim (no auto-stringify)', () async {
      Map<String, dynamic>? captured;
      Future<ToolResult> fakeRun(String name, Map<String, dynamic> args) async {
        captured = Map<String, dynamic>.from(args);
        return ToolResult.ok('ok');
      }

      final adapter = CustomToolAdapter(
        _composedDef([
          {
            'tool': 'anything',
            'args': {
              'count': 42,
              'flag': true,
              'nested': {'a': 1},
              'templated': '{{x}}',
            },
          },
        ]),
      );
      await adapter.execute({
        'x': 'hello',
      }, _testContext(runToolByName: fakeRun));

      expect(captured, isNotNull);
      expect(captured!['count'], 42); // int preserved
      expect(captured!['flag'], true);
      expect(captured!['nested'], {'a': 1}); // map preserved
      expect(captured!['templated'], 'hello'); // template rendered
    });

    test('returns descriptive error when runToolByName is not wired', () async {
      final adapter = CustomToolAdapter(
        _composedDef([
          {'tool': 'x', 'args': <String, dynamic>{}},
        ]),
      );
      final result = await adapter.execute(const {}, _testContext());
      expect(result.success, isFalse);
      expect(result.error, contains('must be invoked'));
    });
  });
}
