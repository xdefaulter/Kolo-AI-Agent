import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'ui/chat/chat_screen.dart';
import 'core/theme_provider.dart';
import 'core/agent/agent_session.dart';
import 'core/agent/agent_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (optional — app works without it)
  try {
    await Firebase.initializeApp();
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  } catch (_) {
    // Firebase not configured yet — app works fine without it
  }

  runApp(const ProviderScope(child: KoloApp()));
}

class KoloApp extends ConsumerWidget {
  const KoloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Initialize custom instructions from DB
    ref.watch(customInstructionsInitProvider);
    // Initialize max iterations from DB
    ref.watch(maxIterationsInitProvider);
    return MaterialApp(
      title: 'Kolo AI Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6744A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6744A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: themeMode,
      home: const ChatScreen(),
    );
  }
}