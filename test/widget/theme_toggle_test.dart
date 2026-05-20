import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo_ai_agent/core/theme_provider.dart';

import '../helpers/test_harness.dart';

void main() {
  setUp(() async {
    await installTestHarness();
  });

  testWidgets('theme mode provider cycles through system/light/dark',
      (tester) async {
    late ThemeMode captured;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref.watch(themeModeProvider);
            return const MaterialApp(home: SizedBox.shrink());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Default before any user action: system.
    expect(captured, ThemeMode.system);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final notifier = container.read(themeModeProvider.notifier);
    notifier.setMode(ThemeMode.dark);
    await tester.pump();
    expect(captured, ThemeMode.dark);

    notifier.setMode(ThemeMode.light);
    await tester.pump();
    expect(captured, ThemeMode.light);
  });
}
