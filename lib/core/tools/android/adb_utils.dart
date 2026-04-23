import 'dart:convert';
import 'dart:io';

/// Shared ADB utilities — extracted from duplicate helpers in
/// adb_phone_controller.dart and scan_phone_apps.dart.

/// Whether ADB is available on this machine.
Future<bool> isAdbAvailable() async {
  try {
    final result = await Process.run('adb', ['version'],
        stdoutEncoding: utf8, stderrEncoding: utf8)
      .timeout(const Duration(seconds: 5));
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Verify a device is connected via ADB.
Future<bool> isAdbConnected() async {
  try {
    final result = await Process.run('adb', ['devices'],
        stdoutEncoding: utf8, stderrEncoding: utf8)
      .timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return false;
    final lines = (result.stdout as String)
        .split('\n')
        .where((l) => l.contains('\tdevice'))
        .toList();
    return lines.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Check ADB connection and return a user-friendly error message, or null if OK.
Future<String?> checkAdbConnection() async {
  if (!await isAdbAvailable()) {
    return 'ADB not found. Install Android SDK platform-tools and add to PATH.';
  }
  if (!await isAdbConnected()) {
    return 'No Android device connected. Connect a device via USB or use "adb connect <ip>:5555".';
  }
  return null;
}

/// Get the connected device's screen dimensions.
/// Returns (width, height). Falls back to (1080, 2400) if unable to determine.
Future<({int width, int height})> getScreenSize() async {
  try {
    final output = await adbShell('wm size');
    // Output: "Physical size: 1080x2400" or "Override size: ..."
    final match = RegExp(r'(\d+)x(\d+)').firstMatch(output);
    if (match != null) {
      return (
        width: int.parse(match.group(1)!),
        height: int.parse(match.group(2)!),
      );
    }
  } catch (_) {}
  return (width: 1080, height: 2400);
}

/// Sanitize an ADB shell command argument.
/// Only allows alphanumeric, spaces, dots, hyphens, underscores, slashes, colons, equals, commas, at signs.
/// Strips shell metacharacters that could enable command injection.
String sanitizeAdbArg(String arg) {
  return arg.replaceAll(RegExp(r'[^a-zA-Z0-9 ._\-/:=,@%]'), '');
}

/// Run an ADB command and return stdout.
Future<String> adb(List<String> args, {int timeoutSec = 15}) async {
  final result = await Process.run('adb', args,
      stdoutEncoding: utf8, stderrEncoding: utf8)
    .timeout(Duration(seconds: timeoutSec));
  if (result.exitCode != 0) {
    final err = (result.stderr as String).trim();
    // User-friendly error messages
    if (err.contains('no devices/emulators found') || err.contains('device not found')) {
      throw Exception('No Android device connected. Connect a device via USB or ADB wireless.');
    }
    if (err.contains('command not found')) {
      throw Exception('ADB not found. Install Android SDK platform-tools and add to PATH.');
    }
    throw Exception('ADB command failed: $err');
  }
  return (result.stdout as String).trim();
}

/// Run an ADB shell command.
Future<String> adbShell(String cmd, {int timeoutSec = 15}) =>
    adb(['shell', cmd], timeoutSec: timeoutSec);

/// Check accessibility service status on the connected device.
Future<String> getAccessibilityStatus() async {
  try {
    final output = await adbShell('settings get secure enabled_accessibility_services', timeoutSec: 5);
    if (output.isEmpty || output == 'null') {
      return 'No accessibility services enabled';
    }
    return 'Enabled services: $output';
  } catch (_) {
    return 'Unable to check accessibility status';
  }
}
