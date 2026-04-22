import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Tracks online/offline state. Emits true when online.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map((results) =>
    results.any((r) => r != ConnectivityResult.none));
});

/// Whether the device is currently online (sync getter, defaults true)
final isOnlineProvider = StateProvider<bool>((ref) {
  final asyncValue = ref.watch(connectivityProvider);
  return asyncValue.when(data: (d) => d, loading: () => true, error: (_, __) => true);
});