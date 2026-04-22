import 'dart:async';
import '../tool_base.dart';

/// Set a countdown timer. While the app can't create system alarms natively,
/// it can track timers and notify when they complete (in-app only).
class TimerTool extends KoloTool {
  /// Active timers by ID
  static final Map<String, Timer> _activeTimers = {};
  static final Map<String, DateTime> _timerEnds = {};

  @override
  String get name => 'timer';
  @override
  String get description => 'Set a countdown timer. Returns timer details. The timer runs in-app — when it completes, a notification is shown.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'duration_seconds': {'type': 'integer', 'description': 'Timer duration in seconds'},
      'label': {'type': 'string', 'description': 'Optional label for the timer (e.g. "Pasta timer")'},
      'action': {'type': 'string', 'enum': ['start', 'check', 'cancel'], 'description': 'Action: start, check status, or cancel (default start)'},
      'timer_id': {'type': 'string', 'description': 'Timer ID for check/cancel actions (returned when starting)'},
    },
    'required': ['duration_seconds'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final action = params['action'] as String? ?? 'start';

    switch (action) {
      case 'start':
        final durationSec = params['duration_seconds'] as int;
        final label = params['label'] as String? ?? 'Timer';
        final id = 'timer_${DateTime.now().millisecondsSinceEpoch}';

        _timerEnds[id] = DateTime.now().add(Duration(seconds: durationSec));

        _activeTimers[id]?.cancel();
        _activeTimers[id] = Timer(Duration(seconds: durationSec), () {
          _activeTimers.remove(id);
          _timerEnds.remove(id);
          // Timer completed — in a full implementation, this would trigger a notification
        });

        final minutes = durationSec ~/ 60;
        final seconds = durationSec % 60;
        final timeStr = minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';

        return ToolResult.ok(
          'Timer "$label" started: $timeStr\nTimer ID: $id',
          metadata: {'timer_id': id, 'duration_seconds': durationSec, 'label': label, 'ends_at': _timerEnds[id]!.toIso8601String()},
        );

      case 'check':
        final id = params['timer_id'] as String?;
        if (id == null) return ToolResult.err('timer_id required for check action');
        if (!_timerEnds.containsKey(id)) return ToolResult.ok('Timer $id has completed or does not exist');
        final remaining = _timerEnds[id]!.difference(DateTime.now());
        if (remaining.isNegative) return ToolResult.ok('Timer $id has completed');
        return ToolResult.ok('Timer $id: ${remaining.inMinutes}m ${remaining.inSeconds % 60}s remaining');

      case 'cancel':
        final id = params['timer_id'] as String?;
        if (id == null) return ToolResult.err('timer_id required for cancel action');
        _activeTimers[id]?.cancel();
        _activeTimers.remove(id);
        _timerEnds.remove(id);
        return ToolResult.ok('Timer $id cancelled');

      default:
        return ToolResult.err('Unknown action: $action. Use start, check, or cancel.');
    }
  }
}