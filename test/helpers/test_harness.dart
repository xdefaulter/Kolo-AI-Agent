import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bootstraps widget-test plumbing that real plugins need:
///   * temp app-documents directory (for AppDatabase JSON files)
///   * SharedPreferences in-memory backing
///   * flutter_secure_storage method-channel stub
///   * Firebase Crashlytics / path-provider channel no-ops
///
/// Call once per test (usually in `setUp`). Returns the temp dir so tests
/// can clean up or poke at file state.
Future<Directory> installTestHarness() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Use a unique tmp dir per test so parallel tests don't collide.
  final tmp = Directory.systemTemp.createTempSync('kolo_test_');
  PathProviderPlatform.instance = _FakePathProvider(tmp.path);

  SharedPreferences.setMockInitialValues(<String, Object>{});

  // flutter_secure_storage uses method channel; stub as in-memory map.
  const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureChannel, (call) async {
    switch (call.method) {
      case 'read':
        return secureStore[call.arguments['key'] as String];
      case 'write':
        secureStore[call.arguments['key'] as String] =
            call.arguments['value'] as String;
        return null;
      case 'delete':
        secureStore.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        secureStore.clear();
        return null;
      case 'containsKey':
        return secureStore.containsKey(call.arguments['key'] as String);
      case 'readAll':
        return Map<String, String>.from(secureStore);
      default:
        return null;
    }
  });

  // Connectivity / battery / geolocator / speech / tts / haptics / share —
  // all method channel plugins that throw under test. Swallow everything.
  const swallowChannels = [
    'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/connectivity_status',
    'dev.fluttercommunity.plus/battery',
    'dev.fluttercommunity.plus/vibrate',
    'flutter.baseflow.com/geolocator',
    'flutter.baseflow.com/permissions/methods',
    'plugins.flutter.io/shared_preferences',
    'flutter_tts',
    'plugin.csars.de/flutter_speech',
    'plugins.flutter.io/share_plus',
  ];
  for (final name in swallowChannels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }

  return tmp;
}

/// Pump an arbitrary widget under a ProviderScope with default MaterialApp.
/// Use when a test needs to exercise one widget in isolation.
Future<void> pumpInApp(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        themeMode: themeMode,
        home: Scaffold(body: child),
      ),
    ),
  );
}

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this._root);

  final String _root;

  @override
  Future<String?> getApplicationDocumentsPath() async => _root;

  @override
  Future<String?> getApplicationSupportPath() async => _root;

  @override
  Future<String?> getTemporaryPath() async => _root;

  @override
  Future<String?> getApplicationCachePath() async => _root;

  @override
  Future<String?> getDownloadsPath() async => _root;

  @override
  Future<String?> getLibraryPath() async => _root;

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async =>
      [_root];
}
