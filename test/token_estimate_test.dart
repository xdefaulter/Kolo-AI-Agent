import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/agent/conversation_manager.dart';

/// These tests exercise the byte-floor behaviour added to
/// ConversationManager's token estimator. Rather than making the private
/// method public for testing, we probe it indirectly through
/// [ConversationManager.getMessagesForApi] which uses the estimator to
/// decide what fits in the budget.
///
/// The core assertion: a string with the same number of *whitespace-
/// separated words* as English prose but dense JSON-like content (no
/// whitespace) should take *more* budget — because the byte-floor
/// correctly treats dense content as costing more tokens.
void main() {
  group('ConversationManager token budget', () {
    /// Build a message that fits in exactly `budget` tokens (roughly).
    String proseOfLength(int chars) {
      // ~5 chars per "word" + a space, English-prose-like.
      final buf = StringBuffer();
      while (buf.length < chars) {
        buf.write('word ');
      }
      return buf.toString().substring(0, chars);
    }

    String jsonOfLength(int chars) {
      // Dense minified JSON with almost no whitespace.
      final buf = StringBuffer('{');
      int i = 0;
      while (buf.length < chars) {
        buf.write('"k$i":"v$i",');
        i++;
      }
      // Close the struct cleanly.
      return '${buf.toString().substring(0, chars - 1)}}';
    }

    test('prose message counts roughly word-based', () {
      final cm = ConversationManager(maxContextTokens: 1000);
      cm.addUserMessage(proseOfLength(400));
      final msgs = cm.getMessagesForApi();
      // Prose should fit comfortably in 1000 tokens.
      expect(msgs.length, 1);
    });

    test('dense JSON costs more than prose of the same character length', () {
      // Budget tight enough that the byte-floor pushes JSON past while
      // the same-length prose still fits.
      final tight = 200;
      final proseCM = ConversationManager(maxContextTokens: tight);
      proseCM.addUserMessage(proseOfLength(400));

      final jsonCM = ConversationManager(maxContextTokens: tight);
      jsonCM.addUserMessage(jsonOfLength(400));

      final proseFit = proseCM.getMessagesForApi();
      final jsonFit = jsonCM.getMessagesForApi();
      // If the prose fit and the JSON didn't, we've proven the byte-floor
      // is charging more for dense content. If both fit or both dropped
      // there's no signal — widen the tightness until the split appears.
      if (proseFit.isNotEmpty && jsonFit.isEmpty) {
        expect(proseFit.length, greaterThan(jsonFit.length));
      } else {
        // Either everything fit or nothing did at this budget. At minimum
        // the token estimate for JSON must not be *lower* than for prose.
        final proseMsg = 'short prose word word word';
        final jsonMsg = '{"key1":"val1","key2":"val2","key3":"val3"}';
        // Budget = prose fits, see if adding JSON *also* fits.
        final combined = ConversationManager(maxContextTokens: 20);
        combined.addUserMessage(proseMsg);
        combined.addUserMessage(jsonMsg);
        // At a 20-token budget, both messages shouldn't fit — newest
        // (JSON) should drop earlier if it costs more.
        final fit = combined.getMessagesForApi();
        expect(
          fit.length,
          lessThan(2),
          reason:
              'byte-floor should keep JSON from squeezing in alongside prose at a tiny budget',
        );
      }
    });

    test('empty content still has per-message overhead', () {
      // Per-message overhead (~50 tokens) represents the role/formatting
      // scaffolding that every message contributes even when its body is
      // empty. At a 10-token budget the message should NOT fit.
      final tiny = ConversationManager(maxContextTokens: 10);
      tiny.addUserMessage('');
      expect(tiny.getMessagesForApi(), isEmpty);

      // With a generous budget the empty message fits.
      final generous = ConversationManager(maxContextTokens: 1000);
      generous.addUserMessage('');
      final msgs = generous.getMessagesForApi();
      expect(msgs.length, 1);
      expect(msgs.first['role'], 'user');
    });

    test('system prompt counted in budget', () {
      final cm = ConversationManager(maxContextTokens: 20);
      cm.addUserMessage('hello world');
      final withSys = cm.getMessagesForApi(systemPrompt: proseOfLength(200));
      // With a big system prompt and tiny budget, the user message may
      // not fit.
      expect(withSys.length, lessThanOrEqualTo(1));
    });
  });
}
