import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'litert_lm_service.dart';

/// Streams the live [LitertLmState] so widgets can rebuild when the
/// engine loads/errors/runs.
final litertLmStateProvider = StreamProvider<LitertLmState>((ref) async* {
  final svc = LitertLmService.instance;
  yield svc.state;
  yield* svc.stateStream;
});
