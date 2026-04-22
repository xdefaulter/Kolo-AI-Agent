import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/database.dart';

/// Max agent loop iterations (default 20, user-configurable)
final maxIterationsProvider = StateProvider<int>((ref) => 20);

/// Async initializer that loads max iterations from DB
final maxIterationsInitProvider = FutureProvider<void>((ref) async {
  final saved = await AppDatabase.instance.getSetting('max_iterations');
  if (saved != null) {
    final parsed = int.tryParse(saved);
    if (parsed != null && parsed >= 1 && parsed <= 100) {
      ref.read(maxIterationsProvider.notifier).state = parsed;
    }
  }
});

/// Save max iterations to DB
Future<void> saveMaxIterations(WidgetRef ref, int value) async {
  ref.read(maxIterationsProvider.notifier).state = value;
  await AppDatabase.instance.saveSetting('max_iterations', value.toString());
}