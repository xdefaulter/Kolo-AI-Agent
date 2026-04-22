import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/tools/tool_bootstrap.dart';
import 'package:kolo_ai_agent/core/agent/conversation_manager.dart';
import 'package:kolo_ai_agent/core/api/provider.dart';

void main() {
  group('ToolRegistry', () {
    test('bootstrapTools registers all expected tools', () {
      final registry = bootstrapTools();
      // 5 original + 2 clipboard + 15 new = 22
      expect(registry.all.length, greaterThanOrEqualTo(22));

      // Check core tools exist
      expect(registry.get('read_file'), isNotNull);
      expect(registry.get('write_file'), isNotNull);
      expect(registry.get('calculator'), isNotNull);
      expect(registry.get('web_search'), isNotNull);
      expect(registry.get('clipboard_read'), isNotNull);
      expect(registry.get('clipboard_write'), isNotNull);
      expect(registry.get('shell_exec'), isNotNull);
      expect(registry.get('http_get'), isNotNull);
    });

    test('getFunctionDefinitions returns valid OpenAI format', () {
      final registry = bootstrapTools();
      final defs = registry.getFunctionDefinitions();

      expect(defs, isNotEmpty);
      for (final def in defs) {
        expect(def, containsPair('type', 'function'));
        expect(def, contains('function'));
        final func = def['function'] as Map<String, dynamic>;
        expect(func, contains('name'));
        expect(func, contains('description'));
        expect(func, contains('parameters'));
      }
    });
  });

  group('ConversationManager', () {
    test('addUserMessage and getMessagesForApi', () {
      final cm = ConversationManager();
      cm.addUserMessage('Hello');
      cm.addAssistantMessage('Hi there!');

      final messages = cm.getMessagesForApi(systemPrompt: 'You are helpful.');
      expect(messages.length, 3); // system + user + assistant
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');
      expect(messages[2]['role'], 'assistant');
    });

    test('token budget trims old messages', () {
      final cm = ConversationManager(maxContextTokens: 100);
      for (int i = 0; i < 50; i++) {
        cm.addUserMessage('Message $i with some content to fill tokens');
      }
      final messages = cm.getMessagesForApi();
      // Should trim to fit budget
      expect(messages.length, lessThan(50));
    });

    test('clear removes all messages', () {
      final cm = ConversationManager();
      cm.addUserMessage('Hello');
      cm.addAssistantMessage('Hi');
      expect(cm.messages.length, 2);
      cm.clear();
      expect(cm.messages.length, 0);
    });
  });

  group('ProviderConfig', () {
    test('serialization roundtrip', () {
      final config = ProviderConfig(
        name: 'Test Provider',
        baseUrl: 'https://api.test.com/v1',
        apiKey: 'test-key-123',
        models: [
          ModelConfig(modelId: 'gpt-4', displayName: 'GPT-4', maxTokens: 4096),
        ],
      );

      final map = config.toMap();
      final restored = ProviderConfig.fromMap(map);

      expect(restored.name, config.name);
      expect(restored.baseUrl, config.baseUrl);
      expect(restored.apiKey, config.apiKey);
      expect(restored.models.length, 1);
      expect(restored.models.first.modelId, 'gpt-4');
    });

    test('activeModel returns first active model', () {
      final config = ProviderConfig(
        name: 'Test',
        baseUrl: 'https://test.com/v1',
        models: [
          ModelConfig(modelId: 'model-a', isActive: false),
          ModelConfig(modelId: 'model-b', isActive: true),
          ModelConfig(modelId: 'model-c', isActive: false),
        ],
      );

      expect(config.activeModel?.modelId, 'model-b');
    });

    test('canFetchModels depends on modelsEndpoint', () {
      final withEndpoint = ProviderConfig(
        name: 'Has endpoint',
        baseUrl: 'https://test.com/v1',
        modelsEndpoint: 'https://test.com/v1/models',
      );
      final withoutEndpoint = ProviderConfig(
        name: 'No endpoint',
        baseUrl: 'https://test.com/v1',
      );

      expect(withEndpoint.canFetchModels, true);
      expect(withoutEndpoint.canFetchModels, false);
    });
  });

  group('ChatMessage', () {
    test('toApiFormat includes all fields', () {
      final msg = ChatMessage(
        role: 'assistant',
        content: 'Hello',
        toolCalls: [
          {'type': 'function', 'function': {'name': 'test', 'arguments': '{}'}},
        ],
      );
      final api = msg.toApiFormat();
      expect(api['role'], 'assistant');
      expect(api['content'], 'Hello');
      expect(api['tool_calls'], isNotNull);
    });

    test('loadMessages adds to conversation', () {
      final cm = ConversationManager();
      cm.addMessage(ChatMessage(role: 'user', content: 'Hi'));
      cm.addMessage(ChatMessage(role: 'assistant', content: 'Hello'));
      expect(cm.messages.length, 2);
    });
  });
}