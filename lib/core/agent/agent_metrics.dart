import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/openai_client.dart' show TokenUsage;

/// Live + cumulative metrics for the current chat session. Exposed via
/// [agentMetricsProvider] so only widgets that watch metrics rebuild —
/// chat message rows stay untouched during streaming ticks.
///
/// Numbers come from two sources:
///   * **Server-authoritative** — [TokenUsage] parsed from the provider's
///     final SSE chunk. Preferred when available.
///   * **Client estimate** — a cheap `content.length ~/ 4` heuristic run
///     only at throttled intervals (≤ 5Hz). Used for live display
///     before the server finalises counts.
class AgentMetricsSnapshot {
  /// Wall-clock duration of the current in-flight turn, or zero when
  /// idle. Updated together with [turnCompletionTokens] on each
  /// throttled tick.
  final Duration turnElapsed;

  /// Time from request start to first content token (TTFT). Null until
  /// the first content chunk arrives.
  final Duration? turnTimeToFirstToken;

  /// Completion tokens for the current turn. While streaming this is a
  /// client-side estimate; when the server's `usage` chunk arrives, it's
  /// replaced with the authoritative count.
  final int turnCompletionTokens;

  /// Server-authoritative prompt tokens for the current turn. Usually
  /// zero until the final chunk arrives (most providers don't stream
  /// prompt counts incrementally).
  final int turnPromptTokens;

  /// Tokens per second for the completion phase. Null when the turn
  /// hasn't produced its first token yet. Divided by wall-clock time
  /// since first token so pre-token thinking doesn't inflate speed.
  final double? turnTokensPerSecond;

  /// Whether we're currently streaming. When false the turn fields
  /// above represent the last completed turn (handy for the UI).
  final bool streaming;

  /// Running cumulative usage since the session started. Monotonic;
  /// reset only via [AgentMetricsNotifier.resetSession].
  final TokenUsage cumulative;

  const AgentMetricsSnapshot({
    required this.turnElapsed,
    required this.turnTimeToFirstToken,
    required this.turnCompletionTokens,
    required this.turnPromptTokens,
    required this.turnTokensPerSecond,
    required this.streaming,
    required this.cumulative,
  });

  static const idle = AgentMetricsSnapshot(
    turnElapsed: Duration.zero,
    turnTimeToFirstToken: null,
    turnCompletionTokens: 0,
    turnPromptTokens: 0,
    turnTokensPerSecond: null,
    streaming: false,
    cumulative: TokenUsage.zero,
  );

  AgentMetricsSnapshot copyWith({
    Duration? turnElapsed,
    Duration? turnTimeToFirstToken,
    int? turnCompletionTokens,
    int? turnPromptTokens,
    double? turnTokensPerSecond,
    bool? streaming,
    TokenUsage? cumulative,
  }) => AgentMetricsSnapshot(
    turnElapsed: turnElapsed ?? this.turnElapsed,
    turnTimeToFirstToken: turnTimeToFirstToken ?? this.turnTimeToFirstToken,
    turnCompletionTokens: turnCompletionTokens ?? this.turnCompletionTokens,
    turnPromptTokens: turnPromptTokens ?? this.turnPromptTokens,
    turnTokensPerSecond: turnTokensPerSecond ?? this.turnTokensPerSecond,
    streaming: streaming ?? this.streaming,
    cumulative: cumulative ?? this.cumulative,
  );
}

/// Drives [agentMetricsProvider]. All mutation is funneled through this
/// notifier so the chat screen + dev screen + app bar chip all render
/// from a single source of truth.
///
/// **Perf contract**: during a streaming turn, [onContentDelta] is called
/// on every chunk BUT state is only pushed at [_throttle] intervals. A
/// single accumulator (int) is O(1) per chunk; no allocations per chunk.
class AgentMetricsNotifier extends StateNotifier<AgentMetricsSnapshot> {
  AgentMetricsNotifier() : super(AgentMetricsSnapshot.idle);

  /// Minimum interval between state pushes while streaming. 250ms keeps
  /// the speed counter readable without burning CPU on rebuilds.
  static const _throttle = Duration(milliseconds: 250);

  // Mutable per-turn accumulators. Kept off `state` to avoid allocating a
  // fresh snapshot on every chunk.
  int _pendingContentChars = 0;
  DateTime? _turnStart;
  DateTime? _firstTokenAt;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hasServerUsage = false;
  int _serverPromptTokens = 0;
  int _serverCompletionTokens = 0;

  /// Mark the start of a new turn (after user send, before first stream
  /// chunk). Resets per-turn accumulators; cumulative is preserved.
  void beginTurn() {
    _pendingContentChars = 0;
    _turnStart = DateTime.now();
    _firstTokenAt = null;
    _hasServerUsage = false;
    _serverPromptTokens = 0;
    _serverCompletionTokens = 0;
    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    state = state.copyWith(
      turnElapsed: Duration.zero,
      turnTimeToFirstToken: null,
      turnCompletionTokens: 0,
      turnPromptTokens: 0,
      turnTokensPerSecond: null,
      streaming: true,
    );
  }

  /// Called on every content/reasoning chunk. Cheap: just increments an
  /// int and maybe pushes a throttled snapshot.
  void onContentDelta(int charsAdded) {
    if (_turnStart == null) return;
    _pendingContentChars += charsAdded;
    _firstTokenAt ??= DateTime.now();
    _maybePushSnapshot();
  }

  /// Server's authoritative usage arrived — overrides the client estimate
  /// for the rest of this turn AND for subsequent idle displays.
  void onServerUsage(TokenUsage usage) {
    _hasServerUsage = true;
    _serverPromptTokens = usage.promptTokens;
    _serverCompletionTokens = usage.completionTokens;
    // Force a push so the authoritative numbers land immediately.
    _pushSnapshot(force: true);
  }

  /// End the turn. If the server sent a `usage` chunk we commit those
  /// counts to cumulative; otherwise we commit the client estimate so
  /// users still see a running total even with providers that omit
  /// usage.
  void endTurn() {
    _pushSnapshot(force: true);
    final estCompletion = _estimateCompletionTokens();
    final completion = _hasServerUsage
        ? _serverCompletionTokens
        : estCompletion;
    final prompt = _hasServerUsage ? _serverPromptTokens : 0;
    state = state.copyWith(
      streaming: false,
      cumulative:
          state.cumulative +
          TokenUsage(
            promptTokens: prompt,
            completionTokens: completion,
            totalTokens: prompt + completion,
          ),
    );
    _turnStart = null;
  }

  /// Reset session — typically called on chat switch / clear.
  void resetSession() {
    _turnStart = null;
    _firstTokenAt = null;
    _pendingContentChars = 0;
    _hasServerUsage = false;
    _serverCompletionTokens = 0;
    _serverPromptTokens = 0;
    state = AgentMetricsSnapshot.idle;
  }

  /// `~4 chars per token` is the cheap industry-standard heuristic. We
  /// don't tokenise — just divide the accumulated character count. Pure
  /// integer math, no allocations.
  int _estimateCompletionTokens() => _pendingContentChars ~/ 4;

  void _maybePushSnapshot() {
    final now = DateTime.now();
    if (now.difference(_lastPush) < _throttle) return;
    _pushSnapshot();
  }

  void _pushSnapshot({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastPush) < _throttle) return;
    _lastPush = now;
    final start = _turnStart;
    if (start == null) return;
    final elapsed = now.difference(start);
    final ttft = _firstTokenAt?.difference(start);
    final completion = _hasServerUsage
        ? _serverCompletionTokens
        : _estimateCompletionTokens();
    final prompt = _hasServerUsage ? _serverPromptTokens : 0;
    double? tps;
    final firstAt = _firstTokenAt;
    if (firstAt != null) {
      final streamDuration = now.difference(firstAt);
      if (streamDuration.inMilliseconds > 250 && completion > 0) {
        tps = completion * 1000 / streamDuration.inMilliseconds;
      }
    }
    state = state.copyWith(
      turnElapsed: elapsed,
      turnTimeToFirstToken: ttft,
      turnCompletionTokens: completion,
      turnPromptTokens: prompt,
      turnTokensPerSecond: tps,
    );
  }
}

final agentMetricsProvider =
    StateNotifierProvider<AgentMetricsNotifier, AgentMetricsSnapshot>(
      (ref) => AgentMetricsNotifier(),
    );
