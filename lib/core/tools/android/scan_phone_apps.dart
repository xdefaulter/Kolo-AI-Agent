import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../tool_base.dart';
import 'adb_utils.dart';

// ════════════════════════════════════════════
// Tool: Scan Phone Apps (via ADB)
// ════════════════════════════════════════════

class ScanPhoneAppsTool extends KoloTool {
  @override
  String get name => 'scan_phone_apps';
  @override
  String get description =>
      'Scan all installed apps via ADB and extract their intent filters, exported activities, '
      'broadcast receivers, content providers, and deep links. '
      'Saves result to app_intents.json for AI context. Works with ADB connection only.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'filter': {
        'type': 'string',
        'description': 'Optional: only scan packages matching this substring (e.g. "com.google")',
      },
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final rawFilter = params['filter'] as String?;
    final filter = rawFilter != null ? sanitizeAdbArg(rawFilter) : null;

    try {
      // Check ADB connection first
      final connErr = await checkAdbConnection();
      if (connErr != null) return ToolResult.err(connErr);
      // 1. Get all installed packages
      final rawPackages = await adbShell('pm list packages -f', timeoutSec: 30);
      final lines = rawPackages.split('\n').where((l) => l.startsWith('package:')).toList();

      // Parse package names
      List<String> packages = lines.map((line) {
        // format: package:/data/app/.../base.apk=com.example.app
        final eqIdx = line.lastIndexOf('=');
        return eqIdx >= 0 ? line.substring(eqIdx + 1).trim() : '';
      }).where((p) => p.isNotEmpty).toList();

      if (filter != null && filter.isNotEmpty) {
        packages = packages.where((p) => p.contains(filter)).toList();
      }

      // 2. For each package, extract intent info via dumpsys
      final apps = <Map<String, dynamic>>[];
      int totalIntents = 0;

      for (final pkg in packages) {
        try {
          final safePkg = sanitizeAdbArg(pkg);
          final dump = await adbShell(
            'dumpsys package $safePkg',
            timeoutSec: 10,
          );

          final appInfo = _parseDumpsys(pkg, dump);
          final intentCount = (appInfo['activities'] as List).length +
              (appInfo['receivers'] as List).length +
              (appInfo['providers'] as List).length +
              (appInfo['deep_links'] as List).length;

          if (intentCount > 0 || appInfo['intent_filters'] != null) {
            totalIntents += intentCount;
            apps.add(appInfo);
          }
        } catch (_) {
          // Skip packages that fail — some system packages may not be dumpable
        }
      }

      // 3. Save to JSON file
      final jsonData = {
        'scanned_at': DateTime.now().toIso8601String(),
        'total_packages': packages.length,
        'apps_with_intents': apps.length,
        'total_intents': totalIntents,
        'apps': apps,
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonData);

      // Save locally
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final koloDir = Directory('${dir.path}/KoloProjects');
      if (!await koloDir.exists()) await koloDir.create(recursive: true);
      final file = File('${koloDir.path}/app_intents.json');
      await file.writeAsString(jsonStr);

      // Also push to device sdcard if possible
      try {
        await adbShell('mkdir -p /sdcard/KoloProjects');
        // Write via a temp local file + push
        final tmpFile = File('${Directory.systemTemp.path}/kolo_app_intents.json');
        await tmpFile.writeAsString(jsonStr);
        await adb(['push', tmpFile.path, '/sdcard/KoloProjects/app_intents.json']);
        tmpFile.deleteSync();
      } catch (_) {
        // Non-critical — local copy is the primary one
      }

      return ToolResult.ok(
        'Scan complete. ${packages.length} packages scanned, '
        '${apps.length} apps with intents found, $totalIntents total intents.\n'
        'Saved to: ${file.path}\n\n'
        'Top apps:\n${_topAppsSummary(apps, 15)}',
      );
    } catch (e) {
      return ToolResult.err('App scan failed: $e');
    }
  }

  /// Parse dumpsys package output into structured data
  Map<String, dynamic> _parseDumpsys(String pkg, String dump) {
    final activities = <Map<String, dynamic>>[];
    final receivers = <Map<String, dynamic>>[];
    final providers = <Map<String, dynamic>>[];
    final deepLinks = <String>[];
    final intentFilters = <Map<String, dynamic>>[];

    // Extract exported activities with their intent filters
    final activitySection = _extractSection(dump, 'Activity Resolver Table:');
    if (activitySection != null) {
      for (final match in RegExp(r'(\S+/\S+)\s+filter\s+\S+\n((?:\s+.+\n)*)')
          .allMatches(activitySection)) {
        final component = match.group(1) ?? '';
        final filterBlock = match.group(2) ?? '';
        if (component.startsWith(pkg) || component.contains(pkg)) {
          final actions = _extractFilterValues(filterBlock, 'Action:');
          final categories = _extractFilterValues(filterBlock, 'Category:');
          final dataSchemes = _extractFilterValues(filterBlock, 'Scheme:');

          activities.add({
            'component': component,
            if (actions.isNotEmpty) 'actions': actions,
            if (categories.isNotEmpty) 'categories': categories,
            if (dataSchemes.isNotEmpty) 'schemes': dataSchemes,
          });

          // Collect deep links
          for (final scheme in dataSchemes) {
            if (scheme != 'http' && scheme != 'https') {
              deepLinks.add(scheme);
            }
          }
        }
      }
    }

    // Extract broadcast receivers
    final receiverSection = _extractSection(dump, 'Receiver Resolver Table:');
    if (receiverSection != null) {
      for (final match in RegExp(r'(\S+/\S+)\s+filter')
          .allMatches(receiverSection)) {
        final component = match.group(1) ?? '';
        if (component.contains(pkg)) {
          receivers.add({'component': component});
        }
      }
    }

    // Extract content providers
    final providerRegex = RegExp('ContentProvider.*?\\{[^}]*$pkg[^}]*\\}', multiLine: true);
    for (final match in providerRegex.allMatches(dump)) {
      providers.add({'info': match.group(0)?.trim() ?? ''});
    }

    // Look for app links (http/https intent filters)
    final httpLinkRegex = RegExp(r'https?://[^\s"]+');
    final appLinksSection = _extractSection(dump, 'App Links:') ?? '';
    for (final match in httpLinkRegex.allMatches(appLinksSection)) {
      deepLinks.add(match.group(0) ?? '');
    }

    // Parse general intent filters
    final filterRegex = RegExp(r'Action:\s+"([^"]+)"');
    for (final match in filterRegex.allMatches(dump)) {
      final action = match.group(1) ?? '';
      if (action.isNotEmpty) {
        intentFilters.add({'action': action});
      }
    }

    return {
      'package': pkg,
      'activities': activities,
      'receivers': receivers,
      'providers': providers,
      'deep_links': deepLinks.toSet().toList(),
      if (intentFilters.isNotEmpty) 'intent_filters': intentFilters.take(20).toList(),
    };
  }

  String? _extractSection(String dump, String header) {
    final idx = dump.indexOf(header);
    if (idx < 0) return null;
    final endIdx = dump.indexOf('\n\n', idx + header.length);
    return endIdx > idx ? dump.substring(idx, endIdx) : dump.substring(idx);
  }

  List<String> _extractFilterValues(String block, String prefix) {
    final values = <String>[];
    for (final line in block.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith(prefix)) {
        final val = trimmed.substring(prefix.length).trim().replaceAll('"', '');
        if (val.isNotEmpty) values.add(val);
      }
    }
    return values;
  }

  String _topAppsSummary(List<Map<String, dynamic>> apps, int limit) {
    // Sort by most intents
    final sorted = List<Map<String, dynamic>>.from(apps)
      ..sort((a, b) {
        final aCount = (a['activities'] as List).length + (a['deep_links'] as List).length;
        final bCount = (b['activities'] as List).length + (b['deep_links'] as List).length;
        return bCount.compareTo(aCount);
      });
    final top = sorted.take(limit);
    return top.map((a) {
      final pkg = a['package'] as String;
      final acts = (a['activities'] as List).length;
      final links = (a['deep_links'] as List).length;
      return '  $pkg — $acts activities, $links deep links';
    }).join('\n');
  }
}

/// Utility: load the app_intents.json summary for AI context injection.
/// Returns null if file doesn't exist.
Future<String?> loadAppIntentsSummary() async {
  try {
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/KoloProjects/app_intents.json');
    if (!await file.exists()) return null;

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final apps = json['apps'] as List? ?? [];
    if (apps.isEmpty) return null;

    final totalPkgs = json['total_packages'] ?? 0;
    final totalIntents = json['total_intents'] ?? 0;

    // Build compressed summary — top 25 apps with their key actions/deep links
    final buffer = StringBuffer();
    buffer.writeln('$totalPkgs packages, $totalIntents intents. Key apps:');

    // Sort by activity count + deep link count
    final sorted = List<Map<String, dynamic>>.from(apps)
      ..sort((a, b) {
        final aCount = (a['activities'] as List).length + (a['deep_links'] as List).length;
        final bCount = (b['activities'] as List).length + (b['deep_links'] as List).length;
        return bCount.compareTo(aCount);
      });

    for (final app in sorted.take(25)) {
      final pkg = app['package'] as String;
      final deepLinks = (app['deep_links'] as List).cast<String>();
      final activities = app['activities'] as List;

      final parts = <String>[pkg];
      if (deepLinks.isNotEmpty) {
        parts.add('links:${deepLinks.take(3).join(',')}');
      }
      if (activities.isNotEmpty) {
        // Extract unique actions
        final actions = <String>{};
        for (final act in activities) {
          if (act is Map && act['actions'] is List) {
            for (final a in act['actions']) {
              actions.add(a.toString().replaceAll('android.intent.action.', ''));
            }
          }
        }
        if (actions.isNotEmpty) {
          parts.add('actions:${actions.take(3).join(',')}');
        }
      }
      buffer.writeln('  ${parts.join(' | ')}');
    }

    return buffer.toString();
  } catch (_) {
    return null;
  }
}
