import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_metrics.dart';

/// Compact inline display of live token + speed counters. Designed to
/// live in a chat app bar or a status bar — rebuilds only when
/// [agentMetricsProvider] changes (throttled to ≤ 5Hz), so it doesn't
/// compete with the message list for frame budget.
///
/// Shows nothing when both the current turn is idle AND no cumulative
/// usage has been recorded yet — avoids visual noise on empty chats.
///
/// Tap to show the full breakdown modal.
class MetricsChip extends ConsumerWidget {
  /// When true, uses a monospace terminal-style look (for dev screen).
  /// Defaults to the surrounding theme's typography (for chat app bar).
  final bool monospace;
  const MetricsChip({super.key, this.monospace = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(agentMetricsProvider);
    final cs = Theme.of(context).colorScheme;

    // Decide whether to render at all. Cheap boolean check; no layout cost.
    final hasTurn =
        m.streaming || m.turnCompletionTokens > 0 || m.turnPromptTokens > 0;
    final hasCumulative = m.cumulative.totalTokens > 0;
    if (!hasTurn && !hasCumulative) return const SizedBox.shrink();

    final label = _buildShortLabel(m);
    return InkWell(
      onTap: () => _showDetails(context, ref),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.streaming)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.bolt,
                  size: 14,
                  color: cs.primary.withValues(alpha: 0.85),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.analytics_outlined,
                  size: 13,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontFamily: monospace ? 'monospace' : null,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact one-line string. During streaming: show tokens/sec + running
  /// completion count. Between turns: the last turn's totals.
  String _buildShortLabel(AgentMetricsSnapshot m) {
    if (m.streaming) {
      final tps = m.turnTokensPerSecond;
      if (tps == null) {
        return m.turnTimeToFirstToken == null
            ? '…'
            : '${_fmtDuration(m.turnElapsed)}';
      }
      return '${_fmtShort(m.turnCompletionTokens)} · ${tps.toStringAsFixed(0)} t/s';
    }
    // Idle display: prefer last turn's authoritative count.
    if (m.turnCompletionTokens > 0) {
      return '↑${_fmtShort(m.turnPromptTokens)} ↓${_fmtShort(m.turnCompletionTokens)}';
    }
    // Fallback: cumulative across the session.
    return '${_fmtShort(m.cumulative.totalTokens)} total';
  }

  void _showDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _MetricsDetailsSheet(),
    );
  }
}

class _MetricsDetailsSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(agentMetricsProvider);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.streaming ? 'Current turn (live)' : 'Last turn',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          _row('Prompt tokens', _fmtInt(m.turnPromptTokens), cs),
          _row('Completion tokens', _fmtInt(m.turnCompletionTokens), cs),
          _row(
            'Time to first token',
            m.turnTimeToFirstToken == null
                ? '—'
                : _fmtMs(m.turnTimeToFirstToken!),
            cs,
          ),
          _row('Elapsed', _fmtDuration(m.turnElapsed), cs),
          _row(
            'Speed',
            m.turnTokensPerSecond == null
                ? '—'
                : '${m.turnTokensPerSecond!.toStringAsFixed(1)} tokens/sec',
            cs,
          ),
          const SizedBox(height: 18),
          Text(
            'Session cumulative',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          _row('Prompt tokens', _fmtInt(m.cumulative.promptTokens), cs),
          _row('Completion tokens', _fmtInt(m.cumulative.completionTokens), cs),
          _row(
            'Total tokens',
            _fmtInt(m.cumulative.totalTokens),
            cs,
            emphasise: true,
          ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value,
    ColorScheme cs, {
    bool emphasise = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtInt(int n) {
  if (n == 0) return '0';
  // Thousands separators — no intl dependency needed.
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _fmtShort(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
  if (n < 1000000) return '${(n / 1000).round()}k';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

String _fmtDuration(Duration d) {
  if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  return '${(d.inSeconds / 60).floor()}m ${d.inSeconds % 60}s';
}

String _fmtMs(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  return '${(d.inMilliseconds / 1000).toStringAsFixed(2)}s';
}
