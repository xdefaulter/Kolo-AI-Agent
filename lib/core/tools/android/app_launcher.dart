import 'dart:convert';
import 'package:flutter/services.dart';
import '../tool_base.dart';

const _channel = MethodChannel('com.kolo.ai/phone_control');

/// Tool: Launch an app by package name using Android Intent.
/// This is the correct way to open apps on Android — not URL schemes.
class LaunchAppTool extends KoloTool {
  @override
  String get name => 'launch_app';
  @override
  String get description =>
      'Launch an installed app by its Android package name (e.g. "com.starbucks.mobileorder" for Starbucks, '
      '"ca.timhortons.android" for Tim Hortons). Use list_installed_apps to find the correct package name first. '
      'This uses a proper Android Intent to launch the app — more reliable than URL schemes.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'package_name': {
        'type': 'string',
        'description': 'Android package name of the app to launch (e.g. "com.starbucks.mobileorder")',
      },
    },
    'required': ['package_name'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final packageName = params['package_name'] as String;
    try {
      final result = await _channel.invokeMethod<Map>('launchApp', {'packageName': packageName});
      if (result != null && result['success'] == true) {
        final appName = result['appName'] ?? packageName;
        return ToolResult.ok('Launched: $appName ($packageName)');
      } else {
        final error = result?['error'] ?? 'Unknown error';
        return ToolResult.err('Failed to launch $packageName: $error');
      }
    } on PlatformException catch (e) {
      if (e.code == 'APP_NOT_FOUND') {
        return ToolResult.err('App not installed: $packageName. Use list_installed_apps to find the correct package name.');
      }
      if (e.code == 'NO_SERVICE') {
        return ToolResult.err('Accessibility service not running. Use phone_start tool first.');
      }
      return ToolResult.err('Launch app failed: ${e.message}');
    } catch (e) {
      return ToolResult.err('Launch app failed: $e');
    }
  }
}

/// Tool: List installed applications on the device.
/// Returns app names and package names, optionally filtered by a search query.
class ListInstalledAppsTool extends KoloTool {
  @override
  String get name => 'list_installed_apps';
  @override
  String get description =>
      'List installed apps on the device. Returns app names and their Android package names. '
      'Use the "query" parameter to filter by name (e.g. "starbucks", "tim", "coffee"). '
      'Use this BEFORE launch_app to find the correct package name.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'Optional filter — search app names containing this string (case-insensitive). '
            'E.g. "star" matches "Starbucks", "tim" matches "Tim Hortons".',
      },
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final query = (params['query'] as String?)?.toLowerCase();
    try {
      final result = await _channel.invokeMethod<String>('listInstalledApps', {'query': query ?? ''});
      if (result == null || result.isEmpty) {
        return ToolResult.ok('No apps found${query != null ? " matching \"$query\"" : ""}.');
      }
      // The Kotlin side returns JSON
      final List<dynamic> apps = jsonDecode(result);
      if (apps.isEmpty) {
        return ToolResult.ok('No apps found${query != null ? " matching \"$query\"" : ""}.');
      }
      // Format nicely
      final lines = <String>[];
      for (final app in apps) {
        final name = app['appName'] ?? '';
        final pkg = app['packageName'] ?? '';
        lines.add('$name → $pkg');
      }
      final total = lines.length;
      final display = lines.length > 50 ? '${lines.sublist(0, 50).join('\n')}\n... ($total total, showing first 50)' : lines.join('\n');
      return ToolResult.ok('Installed apps${query != null ? " matching \"$query\"" : ""} ($total):\n$display');
    } on PlatformException catch (e) {
      return ToolResult.err('List apps failed: ${e.message}');
    } catch (e) {
      return ToolResult.err('List apps failed: $e');
    }
  }
}

/// Tool: Get device info (model, Android version, screen size, etc.)
class DeviceInfoTool extends KoloTool {
  @override
  String get name => 'device_info';
  @override
  String get description =>
      'Get device information: model, manufacturer, Android version, API level, screen resolution, '
      'and whether accessibility/overlay permissions are granted. Use this first to understand the device before taking actions.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {},
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      final result = await _channel.invokeMethod<Map>('deviceInfo');
      if (result == null) {
        return ToolResult.err('Failed to get device info');
      }
      final lines = <String>[
        'Device: ${result['manufacturer']} ${result['model']}',
        'Android: ${result['version']} (API ${result['apiLevel']})',
        'Screen: ${result['width']}x${result['height']}',
        'Accessibility: ${result['accessibilityEnabled'] == true ? "enabled" : "disabled"}',
        'Overlay: ${result['overlayEnabled'] == true ? "granted" : "not granted"}',
      ];
      return ToolResult.ok(lines.join('\n'));
    } catch (e) {
      return ToolResult.err('Device info failed: $e');
    }
  }
}