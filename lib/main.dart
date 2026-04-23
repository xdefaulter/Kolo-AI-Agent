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

class KoloApp extends ConsumerStatefulWidget {
  const KoloApp({super.key});

  @override
  ConsumerState<KoloApp> createState() => _KoloAppState();
}

class _KoloAppState extends ConsumerState<KoloApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes from background, evict stale idle connections.
    // The OS may have reclaimed sockets while we were paused — replacing the
    // adapter discards those dead connections without killing the Dio instance.
    // We do NOT cancel active streams here — short background trips (checking
    // a notification) are fine; the server keeps the SSE connection alive.
    if (state == AppLifecycleState.resumed) {
      final session = ref.read(agentSessionProvider.notifier).session;
      session?.closeStaleConnections();
    }
  }

  @override
  Widget build(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 2.6: Only build the active tab instead of IndexedStack keeping both alive
    final Widget body = _currentIndex == 0 ? const ChatScreen() : const DevScreen();
    return Scaffold(
      body: body,
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