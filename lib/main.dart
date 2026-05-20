import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'ui/chat/chat_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'core/theme_provider.dart';
import 'core/agent/agent_session.dart';
import 'core/agent/agent_settings.dart';
import 'core/stt_service.dart';
import 'core/storage/database.dart';
import 'core/bootstrap/bootstrap_service.dart';
import 'core/llm/llama_server_service.dart';

void main() async {
  // IMPORTANT: WidgetsFlutterBinding must be initialised in the ROOT zone.
  // If this runs inside runZonedGuarded, Flutter's engine and framework end
  // up bound to different zones, the first frame never schedules, and the
  // app sits on a black screen forever with no error in logcat. Modern
  // Flutter also catches async errors via PlatformDispatcher.onError, which
  // makes runZonedGuarded redundant for our use case.
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init is best-effort. When absent (no google-services.json,
  // running on a fresh clone, etc.) we degrade to no-op error reporting
  // rather than blocking startup.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('[firebase] init failed, crash reporting disabled: $e');
  }

  if (firebaseReady) {
    // Flutter framework errors (widget lifecycle, build, etc.).
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    // Uncaught async errors on the engine's platform dispatcher (plugin
    // callbacks, native channel errors, unhandled Futures). Covers what
    // runZonedGuarded used to cover without the zone-binding pitfall.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // DB init wrapped so a corrupt store doesn't brick launch — we still
  // want the UI up so the user can wipe data or re-onboard.
  try {
    await AppDatabase.instance.initialize();
  } catch (e, st) {
    debugPrint('[db] init failed, launching anyway: $e\n$st');
  }

  unawaited(SttService.instance.init());
  if (Platform.isAndroid) {
    unawaited(
      BootstrapService.instance.initialize().then((status) {
        debugPrint('[Bootstrap] ${status.message}');
      }),
    );
  }
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
    switch (state) {
      case AppLifecycleState.resumed:
        // The OS may have reclaimed sockets while we were paused —
        // replacing the Dio adapter discards dead connections without
        // killing the instance. We do NOT cancel active streams; short
        // background trips are fine and the server keeps SSE alive.
        final session = ref.read(agentSessionProvider.notifier).session;
        session?.closeStaleConnections();
      case AppLifecycleState.detached:
        // User fully closed the app (task-manager swipe). Stop the
        // llama-server subprocess so the 2–4 GB model doesn't remain
        // resident in RAM after we're gone. Any in-flight request
        // will error out in Dio, which is the right signal upstream.
        // Fire-and-forget — Android gives us ~3s before force-killing.
        // ignore: unawaited_futures
        LlamaServerService.instance.stop();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Keep the server running on brief backgrounding (notification
        // check, transient split-screen). Stopping + reloading a 2 GB
        // model on every app-switch would make the product unusable.
        break;
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
      home: const _FirstRunGate(),
    );
  }
}

/// Routes to [OnboardingScreen] on first launch, otherwise to the normal
/// main navigator. Keeps routing logic out of the onboarding flow itself.
class _FirstRunGate extends ConsumerWidget {
  const _FirstRunGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(onboardingCompleteProvider);
    return status.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _MainNavigator(),
      data: (done) => done ? const _MainNavigator() : const OnboardingScreen(),
    );
  }
}

/// Main app surface: chat-first assistant.
class _MainNavigator extends StatelessWidget {
  const _MainNavigator();

  @override
  Widget build(BuildContext context) {
    return const ChatScreen();
  }
}
