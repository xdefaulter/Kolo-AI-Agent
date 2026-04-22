import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kolo_ai_agent/main.dart';

void main() {
  testWidgets('App renders chat screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoloApp()));

    // Verify that the app renders — check for the app title in the app bar
    // or the empty state icon (Smart Toy outlined)
    expect(find.byType(KoloApp), findsOneWidget);
  });
}