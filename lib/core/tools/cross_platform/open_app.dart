import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../tool_base.dart';

/// Open a URL / deep link using url_launcher.
/// For opening apps by package name, use launch_app instead — this tool
/// only works for registered URL schemes (tel:, sms:, mailto:, https:, etc).
class OpenAppTool extends KoloTool {
  @override
  String get name => 'open_app';
  @override
  String get description =>
      'Open a URL scheme or deep link. ONLY works for registered schemes like tel:, sms:, mailto:, maps:, https:. '
      'This will NOT open apps by package name — use launch_app for that. '
      'Examples: "tel:+1234567890", "sms:+1234567890", "mailto:test@example.com", "https://google.com"';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL scheme or deep link to open (e.g. "tel:+1234567890", "mailto:test@example.com", "https://google.com"). Do NOT use guessed app schemes like "starbucks://" — they rarely work.'},
    },
    'required': ['url'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final url = params['url'] as String;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          return ToolResult.ok('Opened: $url');
        } else {
          return ToolResult.err('Failed to launch: $url');
        }
      } else {
        return ToolResult.err('No app can handle: $url. If trying to open an app, use list_installed_apps to find the package name, then launch_app to open it.');
      }
    } catch (e) {
      return ToolResult.err('Open app failed: $e. If trying to open an app by name, use list_installed_apps + launch_app instead.');
    }
  }
}