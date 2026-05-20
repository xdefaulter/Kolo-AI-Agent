import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/api/chat_client.dart';
import 'package:kolo_ai_agent/core/api/llama_cpp_client.dart';
import 'package:kolo_ai_agent/core/api/openai_client.dart';
import 'package:kolo_ai_agent/core/api/provider.dart';

void main() {
  group('ProviderKind wire format', () {
    test('round-trips through toMap / fromMap', () {
      final original = ProviderConfig(
        name: 'Local Qwen',
        baseUrl: 'file:///local',
        kind: ProviderKind.localLlama,
        modelPath: '/data/data/app/files/models/qwen.gguf',
        disabledTools: {'web_search', 'adb_type_text'},
        smallModelMode: true,
      );
      final roundTripped = ProviderConfig.fromMap(original.toMap());
      expect(roundTripped.kind, ProviderKind.localLlama);
      expect(
        roundTripped.modelPath,
        '/data/data/app/files/models/qwen.gguf',
      );
      expect(roundTripped.disabledTools, {'web_search', 'adb_type_text'});
      expect(roundTripped.smallModelMode, isTrue);
    });

    test('legacy config without kind defaults to openaiCompat', () {
      // Simulate a map written by an older build that didn't have the
      // new fields. All new fields should come back as safe defaults.
      final legacy = <String, dynamic>{
        'id': 'p1',
        'name': 'OpenAI',
        'baseUrl': 'https://api.openai.com/v1',
        'apiKey': '',
        'customHeaders': <String, String>{},
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'models': <Map<String, dynamic>>[],
      };
      final cfg = ProviderConfig.fromMap(legacy);
      expect(cfg.kind, ProviderKind.openaiCompat);
      expect(cfg.modelPath, isNull);
      expect(cfg.disabledTools, isEmpty);
      expect(cfg.smallModelMode, isFalse);
    });
  });

  group('buildChatClient dispatch', () {
    ApiProvider openai() => ApiProvider(
          id: '1',
          name: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-x',
          model: 'gpt-4o',
        );
    ApiProvider local() => ApiProvider(
          id: '2',
          name: 'Local',
          baseUrl: '',
          apiKey: '',
          model: 'local',
          kind: ProviderKind.localLlama,
          modelPath: '/tmp/fake.gguf',
        );

    test('openaiCompat builds an OpenAIClient', () {
      expect(buildChatClient(openai()), isA<OpenAIClient>());
    });

    test('localLlama builds a LlamaCppClient', () {
      expect(buildChatClient(local()), isA<LlamaCppClient>());
    });
  });

  group('LlamaCppClient pre-install guard', () {
    // The real `chatStream` depends on LlamaServerService state, which
    // in turn depends on BootstrapService. In a widget-test runtime
    // neither has been initialised, so we expect the client to bail
    // out with a user-friendly "bootstrap pending" error rather than
    // crashing. Phase 2 owns the server lifecycle; deeper integration
    // tests live behind a device harness, not the unit suite.
    test('returns a setup-required error when bootstrap/server are inactive',
        () async {
      final client = LlamaCppClient(ApiProvider(
        id: '1',
        name: 'Local',
        baseUrl: '',
        apiKey: '',
        model: 'x',
        kind: ProviderKind.localLlama,
        modelPath: '/tmp/whatever.gguf',
      ));
      final chunks = await client
          .chatStream(messages: const [], tools: const [])
          .toList();
      expect(chunks, hasLength(1));
      // We don't care which specific message lands — just that it's a
      // non-null error payload (vs silently hanging / crashing).
      expect(chunks.single.error, isNotNull);
    });
  });
}
