import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/ui/chat/chat_message_ui.dart';

void main() {
  group('ChatMessageUI.id', () {
    test('uses tc:<toolCallId> when toolCallId is set', () {
      final m = ChatMessageUI(
        role: 'tool',
        content: 'result',
        toolCallId: 'abc123',
      );
      expect(m.id, 'tc:abc123');
    });

    test('falls back to role:timestampMicros when no toolCallId', () {
      final ts = DateTime.utc(2026, 4, 23, 12, 0, 0);
      final m = ChatMessageUI(role: 'assistant', content: 'hi', timestamp: ts);
      expect(m.id, 'assistant:${ts.microsecondsSinceEpoch}');
    });

    test('different role or timestamp yields different id', () {
      final ts = DateTime.utc(2026, 4, 23, 12, 0, 0);
      final user = ChatMessageUI(role: 'user', content: 'a', timestamp: ts);
      final assistant = ChatMessageUI(
        role: 'assistant',
        content: 'b',
        timestamp: ts,
      );
      expect(user.id, isNot(assistant.id));
    });

    test('id is stable across rebuilds (same instance)', () {
      final m = ChatMessageUI(
        role: 'user',
        content: 'hi',
        timestamp: DateTime.utc(2026, 4, 23, 12, 0, 0),
      );
      expect(m.id, m.id); // calling twice yields the same value
    });
  });

  group('ChatMessageUI.formattedTimestamp', () {
    test('returns null when timestamp is null', () {
      final m = ChatMessageUI(role: 'user', content: 'hi');
      expect(m.formattedTimestamp, isNull);
    });

    test('formats AM times correctly', () {
      final m = ChatMessageUI(
        role: 'user',
        content: 'hi',
        timestamp: DateTime(2026, 4, 23, 9, 5),
      );
      expect(m.formattedTimestamp, '9:05 AM');
    });

    test('formats PM times correctly', () {
      final m = ChatMessageUI(
        role: 'user',
        content: 'hi',
        timestamp: DateTime(2026, 4, 23, 14, 30),
      );
      expect(m.formattedTimestamp, '2:30 PM');
    });

    test('formats midnight and noon correctly', () {
      final midnight = ChatMessageUI(
        role: 'user',
        content: 'hi',
        timestamp: DateTime(2026, 4, 23, 0, 0),
      );
      final noon = ChatMessageUI(
        role: 'user',
        content: 'hi',
        timestamp: DateTime(2026, 4, 23, 12, 0),
      );
      expect(midnight.formattedTimestamp, '12:00 AM');
      expect(noon.formattedTimestamp, '12:00 PM');
    });

    test('pads single-digit minutes', () {
      final m = ChatMessageUI(
        role: 'user',
        content: 'hi',
        timestamp: DateTime(2026, 4, 23, 3, 5),
      );
      expect(m.formattedTimestamp, '3:05 AM');
    });

    test('caches the formatted value — two calls return same String', () {
      final m = ChatMessageUI(
        role: 'user',
        content: 'hi',
        timestamp: DateTime(2026, 4, 23, 3, 5),
      );
      final first = m.formattedTimestamp;
      final second = m.formattedTimestamp;
      // Equal content AND identical instance (cached, not rebuilt).
      expect(identical(first, second), isTrue);
    });
  });

  group('ChatMessageUI.formatTimestampForTest (pure helper)', () {
    test('can be called without constructing a message', () {
      expect(
        ChatMessageUI.formatTimestampForTest(DateTime(2026, 1, 1, 7, 8)),
        '7:08 AM',
      );
    });
  });
}
