import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'ui/chat/chat_screen.dart';
import 'ui/dev/dev_screen.dart';
import 'core/theme_provider.dart';
import 'core/agent/agent_session.dart';
import 'core/agent/agent_settings.dart';
import 'core/stt_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (optional — app works without it)
  try {
    await Firebase.initializeApp();
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  } catch (_) {
    // Firebase not configured yet — app works fine without it
  }

  // Pre-initialize STT (checks availability, requests permissions on first use)
  SttService.instance.init();

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
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      home: const _MainNavigator(),
    );
  }
}

/// Bottom navigation: Chat + Dev mode
class _MainNavigator extends StatefulWidget {
  const _MainNavigator();

  @override
  State<_MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<_MainNavigator> {
  int _currentIndex = 0;

  static const _screens = [
    ChatScreen(),
    DevScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        height: 56,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline, color: cs.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.chat_bubble, color: cs.primary),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal, color: cs.onSurface.withValues(alpha: 0.6)),
            selectedIcon: Icon(Icons.terminal, color: cs.primary),
            label: 'Dev',
          ),
        ],
      ),
    );
  }
}