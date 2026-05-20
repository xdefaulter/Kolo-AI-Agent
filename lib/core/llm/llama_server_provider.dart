import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llama_server_service.dart';

/// Streams the live [LlamaServerState] so widgets can rebuild when the
/// server starts/stops/crashes. Kicks [LlamaServerService.refresh] once
/// on subscription so first paint reflects reality (bootstrap may have
/// finished after our static field was initialised).
final llamaServerStateProvider = StreamProvider<LlamaServerState>((ref) async* {
  final svc = LlamaServerService.instance;
  // Fire-and-forget refresh so early subscribers don't see a stale
  // `bootstrapPending` until the next state change.
  // ignore: unawaited_futures
  svc.refresh();
  yield svc.state;
  yield* svc.stateStream;
});

/// Rolling buffer of the last ~N lines from the llama-server + apt
/// process streams. Widgets use this instead of subscribing to
/// `logStream` directly so a rebuild mid-install doesn't drop lines.
///
/// Log events are *batched* — apt install bursts hundreds of lines in
/// a single frame, and emitting a fresh immutable `List<String>` per
/// line turns out to be the single largest GC allocator in the app
/// during setup. We buffer incoming lines and flush on a 60-ms timer
/// (one frame at 16 fps — cheap enough to feel live, coarse enough
/// that we're not re-allocating 200 times per apt output chunk).
final llamaServerLogsProvider =
    StateNotifierProvider<_LogTailNotifier, List<String>>((ref) {
      return _LogTailNotifier(ref);
    });

class _LogTailNotifier extends StateNotifier<List<String>> {
  static const _maxLines = 200;
  static const _flushInterval = Duration(milliseconds: 60);

  _LogTailNotifier(Ref ref) : super(const []) {
    _sub = LlamaServerService.instance.logStream.listen((line) {
      _pending.add(line);
      _flushTimer ??= Timer(_flushInterval, _flush);
    });
    ref.onDispose(() {
      _sub.cancel();
      _flushTimer?.cancel();
    });
  }

  late final StreamSubscription<String> _sub;
  final List<String> _pending = [];
  Timer? _flushTimer;

  void _flush() {
    _flushTimer = null;
    if (!mounted || _pending.isEmpty) return;
    // One allocation per frame instead of one per line.
    final next = [...state, ..._pending];
    _pending.clear();
    if (next.length > _maxLines) {
      next.removeRange(0, next.length - _maxLines);
    }
    state = next;
  }

  void clear() {
    _pending.clear();
    state = const [];
  }
}
