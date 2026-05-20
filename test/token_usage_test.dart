import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/agent/agent_metrics.dart';
import 'package:kolo_ai_agent/core/api/openai_client.dart';

void main() {
  group('TokenUsage.fromJson', () {
    test('parses the standard OpenAI shape', () {
      final u = TokenUsage.fromJson({
        'prompt_tokens': 42,
        'completion_tokens': 10,
        'total_tokens': 52,
      });
      expect(u, isNotNull);
      expect(u!.promptTokens, 42);
      expect(u.completionTokens, 10);
      expect(u.totalTokens, 52);
    });

    test('derives total from prompt + completion when server omits it', () {
      final u = TokenUsage.fromJson({
        'prompt_tokens': 20,
        'completion_tokens': 5,
      });
      expect(u, isNotNull);
      expect(u!.totalTokens, 25);
    });

    test('returns null for missing required fields', () {
      expect(TokenUsage.fromJson({'prompt_tokens': 1}), isNull);
      expect(TokenUsage.fromJson({'completion_tokens': 1}), isNull);
      expect(TokenUsage.fromJson(null), isNull);
      expect(TokenUsage.fromJson('not a map'), isNull);
    });

    test('accepts numeric strings? no — strict types, fail closed', () {
      // Defensive: some clients serialise numbers as strings. We reject
      // these so we never silently double-count on accident.
      expect(
        TokenUsage.fromJson({'prompt_tokens': '10', 'completion_tokens': 5}),
        isNull,
      );
    });
  });

  group('TokenUsage arithmetic', () {
    test('+ sums each field', () {
      const a = TokenUsage(
        promptTokens: 10,
        completionTokens: 20,
        totalTokens: 30,
      );
      const b = TokenUsage(
        promptTokens: 5,
        completionTokens: 15,
        totalTokens: 20,
      );
      final sum = a + b;
      expect(sum.promptTokens, 15);
      expect(sum.completionTokens, 35);
      expect(sum.totalTokens, 50);
    });

    test('zero is the identity', () {
      const a = TokenUsage(
        promptTokens: 7,
        completionTokens: 13,
        totalTokens: 20,
      );
      expect(a + TokenUsage.zero, a);
      expect(TokenUsage.zero + a, a);
    });

    test('equality uses all three fields', () {
      expect(
        const TokenUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3),
        const TokenUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3),
      );
      expect(
        const TokenUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3),
        isNot(
          const TokenUsage(
            promptTokens: 1,
            completionTokens: 2,
            totalTokens: 4,
          ),
        ),
      );
    });
  });

  group('AgentMetricsNotifier lifecycle', () {
    test('beginTurn resets per-turn fields but preserves cumulative', () {
      final n = AgentMetricsNotifier();
      // Prime cumulative via a fake completed turn.
      n.beginTurn();
      n.onServerUsage(
        const TokenUsage(
          promptTokens: 100,
          completionTokens: 50,
          totalTokens: 150,
        ),
      );
      n.endTurn();
      expect(n.state.cumulative.totalTokens, 150);

      // New turn: per-turn fields reset, cumulative preserved.
      n.beginTurn();
      expect(n.state.streaming, isTrue);
      expect(n.state.turnCompletionTokens, 0);
      expect(n.state.cumulative.totalTokens, 150);
    });

    test('endTurn commits server usage to cumulative when present', () {
      final n = AgentMetricsNotifier();
      n.beginTurn();
      n.onServerUsage(
        const TokenUsage(
          promptTokens: 30,
          completionTokens: 70,
          totalTokens: 100,
        ),
      );
      n.endTurn();
      expect(n.state.cumulative.promptTokens, 30);
      expect(n.state.cumulative.completionTokens, 70);
      expect(n.state.cumulative.totalTokens, 100);
      expect(n.state.streaming, isFalse);
    });

    test(
      'endTurn falls back to client estimate when server usage is missing',
      () {
        final n = AgentMetricsNotifier();
        n.beginTurn();
        // 400 chars → ~100 estimated completion tokens (char/4).
        n.onContentDelta(400);
        n.endTurn();
        expect(n.state.cumulative.completionTokens, 100);
        // Prompt tokens default to 0 when not server-reported.
        expect(n.state.cumulative.promptTokens, 0);
        expect(n.state.cumulative.totalTokens, 100);
      },
    );

    test('resetSession zeroes cumulative', () {
      final n = AgentMetricsNotifier();
      n.beginTurn();
      n.onServerUsage(
        const TokenUsage(
          promptTokens: 10,
          completionTokens: 10,
          totalTokens: 20,
        ),
      );
      n.endTurn();
      n.resetSession();
      expect(n.state.cumulative, TokenUsage.zero);
      expect(n.state.streaming, isFalse);
    });

    test('onContentDelta before beginTurn is a no-op', () {
      final n = AgentMetricsNotifier();
      n.onContentDelta(100);
      // No turn active → no state change beyond idle defaults.
      expect(n.state.turnCompletionTokens, 0);
      expect(n.state.turnTimeToFirstToken, isNull);
    });

    test('multiple turns accumulate correctly', () {
      final n = AgentMetricsNotifier();
      // Turn 1: 50 tokens.
      n.beginTurn();
      n.onServerUsage(
        const TokenUsage(
          promptTokens: 20,
          completionTokens: 30,
          totalTokens: 50,
        ),
      );
      n.endTurn();
      // Turn 2: 100 tokens.
      n.beginTurn();
      n.onServerUsage(
        const TokenUsage(
          promptTokens: 40,
          completionTokens: 60,
          totalTokens: 100,
        ),
      );
      n.endTurn();
      expect(n.state.cumulative.promptTokens, 60);
      expect(n.state.cumulative.completionTokens, 90);
      expect(n.state.cumulative.totalTokens, 150);
    });
  });
}
