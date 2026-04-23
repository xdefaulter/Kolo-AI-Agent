import 'dart:convert';
import 'dart:io';
import '../tool_base.dart';
import 'adb_utils.dart';

// ════════════════════════════════════════════
// ADB Tap
// ════════════════════════════════════════════

class AdbTapTool extends KoloTool {
  @override String get name => 'tap';
  @override String get description => 'Tap at screen coordinates via ADB.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'x': {'type': 'number', 'description': 'X coordinate'},
      'y': {'type': 'number', 'description': 'Y coordinate'},
    },
    'required': ['x', 'y'],
  };
  @override ToolPermission get permission => ToolPermission.dangerous;
  @override ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final x = (params['x'] as num).toInt();
    final y = (params['y'] as num).toInt();
    try {
      await adbShell('input tap $x $y');
      return ToolResult.ok('Tapped at ($x, $y) via ADB');
    } catch (e) {
      return ToolResult.err('ADB tap failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// ADB Swipe
// ════════════════════════════════════════════

class AdbSwipeTool extends KoloTool {
  @override String get name => 'swipe';
  @override String get description => 'Swipe gesture via ADB.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'startX': {'type': 'number'},
      'startY': {'type': 'number'},
      'endX': {'type': 'number'},
      'endY': {'type': 'number'},
      'duration': {'type': 'integer', 'description': 'Duration in ms (default 300)'},
    },
    'required': ['startX', 'startY', 'endX', 'endY'],
  };
  @override ToolPermission get permission => ToolPermission.dangerous;
  @override ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final sx = (params['startX'] as num).toInt();
    final sy = (params['startY'] as num).toInt();
    final ex = (params['endX'] as num).toInt();
    final ey = (params['endY'] as num).toInt();
    final dur = params['duration'] as int? ?? 300;
    try {
      await adbShell('input swipe $sx $sy $ex $ey $dur');
      return ToolResult.ok('Swiped ($sx,$sy)→($ex,$ey) ${dur}ms via ADB');
    } catch (e) {
      return ToolResult.err('ADB swipe failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// ADB Type Text
// ════════════════════════════════════════════

class AdbTypeTextTool extends KoloTool {
  @override String get name => 'type_text';
  @override String get description => 'Type text into the focused input via ADB.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'Text to type'},
    },
    'required': ['text'],
  };
  @override ToolPermission get permission => ToolPermission.dangerous;
  @override ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final text = params['text'] as String;
    // ADB input text doesn't handle spaces — replace with %s
    // 1.7: Sanitize text to prevent shell injection via ADB
    final sanitized = sanitizeAdbArg(text);
    final escaped = sanitized.replaceAll(' ', '%s');
    try {
      await adbShell('input text "$escaped"');
      return ToolResult.ok('Typed "$text" via ADB');
    } catch (e) {
      return ToolResult.err('ADB type failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// ADB Press Key
// ════════════════════════════════════════════

class AdbPressKeyTool extends KoloTool {
  @override String get name => 'press_key';
  @override String get description => 'Press a key via ADB keyevent. Common codes: back=4, home=3, recents=187, enter=66, power=26, volume_up=24, volume_down=25, tab=61.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'key': {'type': 'string', 'description': 'Key name (back, home, recents, enter, power) or numeric keycode'},
    },
    'required': ['key'],
  };
  @override ToolPermission get permission => ToolPermission.dangerous;
  @override ToolPlatform get platform => ToolPlatform.android;

  static const _keycodes = {
    'back': 4, 'home': 3, 'recents': 187, 'enter': 66, 'power': 26,
    'volume_up': 24, 'volume_down': 25, 'tab': 61, 'delete': 67,
    'notifications': 83, 'menu': 82,
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final key = params['key'] as String;
    final code = _keycodes[key] ?? int.tryParse(key);
    if (code == null) return ToolResult.err('Unknown key: $key');
    try {
      await adbShell('input keyevent $code');
      return ToolResult.ok('Pressed key $key ($code) via ADB');
    } catch (e) {
      return ToolResult.err('ADB keyevent failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// ADB Screenshot
// ════════════════════════════════════════════

class AdbScreenshotTool extends KoloTool {
  @override String get name => 'screenshot';
  @override String get description => 'Take a screenshot via ADB, returns base64-encoded PNG.';
  @override Map<String, dynamic> get parameterSchema => {'type': 'object', 'properties': {}, 'required': []};
  @override ToolPermission get permission => ToolPermission.sensitive;
  @override ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      // Capture screenshot on device
      await adbShell('screencap -p /sdcard/kolo_screen.png');
      // Pull to local temp
      final tmpDir = Directory.systemTemp;
      final localPath = '${tmpDir.path}/kolo_adb_screen.png';
      await adb(['pull', '/sdcard/kolo_screen.png', localPath]);
      // Read and base64 encode
      final bytes = await File(localPath).readAsBytes();
      final b64 = base64Encode(bytes);
      // Clean up
      await adbShell('rm /sdcard/kolo_screen.png');
      File(localPath).deleteSync();
      return ToolResult.ok('Screenshot captured via ADB (${b64.length} chars)', metadata: {
        'image_base64': b64,
        'format': 'png',
      });
    } catch (e) {
      return ToolResult.err('ADB screenshot failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// ADB Dump UI (uiautomator)
// ════════════════════════════════════════════

class AdbDumpUiTool extends KoloTool {
  @override String get name => 'screen_read';
  @override String get description => 'Dump the UI hierarchy via ADB uiautomator. Returns structured JSON with text, bounds, clickable attributes for all UI elements.';
  @override Map<String, dynamic> get parameterSchema => {'type': 'object', 'properties': {}, 'required': []};
  @override ToolPermission get permission => ToolPermission.sensitive;
  @override ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      // Dump UI on device
      await adbShell('uiautomator dump /sdcard/kolo_ui.xml', timeoutSec: 20);
      // Pull XML
      final tmpDir = Directory.systemTemp;
      final localPath = '${tmpDir.path}/kolo_ui.xml';
      await adb(['pull', '/sdcard/kolo_ui.xml', localPath]);
      final xml = await File(localPath).readAsString();
      // Clean up remote + local
      await adbShell('rm /sdcard/kolo_ui.xml');
      File(localPath).deleteSync();
      // Parse XML to JSON
      final nodes = _parseUiXml(xml);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(nodes);
      if (jsonStr.length > 15000) {
        return ToolResult.ok('Screen UI (truncated):\n${jsonStr.substring(0, 15000)}...\n\n(${nodes.length} elements total)');
      }
      return ToolResult.ok('Screen UI (${nodes.length} elements):\n$jsonStr');
    } catch (e) {
      return ToolResult.err('ADB UI dump failed: $e');
    }
  }

  /// Parse uiautomator XML into a flat list of element maps
  List<Map<String, dynamic>> _parseUiXml(String xml) {
    final nodes = <Map<String, dynamic>>[];
    // Match <node ...attributes... />  or <node ...attributes... >
    final nodeRegex = RegExp(r'<node\s([^>]+?)/?>', dotAll: true);
    final attrRegex = RegExp(r'(\w[\w-]*)="([^"]*)"');

    for (final match in nodeRegex.allMatches(xml)) {
      final attrs = <String, String>{};
      for (final attrMatch in attrRegex.allMatches(match.group(1)!)) {
        attrs[attrMatch.group(1)!] = attrMatch.group(2)!;
      }
      // Only include nodes that have text or are clickable/focusable
      final text = attrs['text'] ?? '';
      final contentDesc = attrs['content-desc'] ?? '';
      final clickable = attrs['clickable'] == 'true';
      final focused = attrs['focused'] == 'true';
      final enabled = attrs['enabled'] == 'true';

      if (text.isNotEmpty || contentDesc.isNotEmpty || clickable) {
        final node = <String, dynamic>{
          if (text.isNotEmpty) 'text': text,
          if (contentDesc.isNotEmpty) 'content_desc': contentDesc,
          'class': attrs['class'] ?? '',
          'bounds': attrs['bounds'] ?? '',
          'clickable': clickable,
          if (focused) 'focused': true,
          if (!enabled) 'enabled': false,
          if (attrs['resource-id']?.isNotEmpty == true) 'id': attrs['resource-id'],
          if (attrs['checkable'] == 'true') 'checkable': true,
          if (attrs['checked'] == 'true') 'checked': true,
          if (attrs['scrollable'] == 'true') 'scrollable': true,
        };
        nodes.add(node);
      }
    }
    return nodes;
  }
}

// ════════════════════════════════════════════
// ADB Scroll (convenience — uses swipe)
// ════════════════════════════════════════════

class AdbScrollTool extends KoloTool {
  @override String get name => 'scroll';
  @override String get description => 'Scroll the screen in a direction via ADB swipe gesture.';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
    },
    'required': [],
  };
  @override ToolPermission get permission => ToolPermission.dangerous;
  @override ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final direction = params['direction'] as String? ?? 'down';
    // 8.1: Query actual screen dimensions instead of hardcoded values
    final screen = await getScreenSize();
    final cx = screen.width ~/ 2;
    final cy = screen.height ~/ 2;
    final dist = screen.height ~/ 4;
    int sx, sy, ex, ey;
    switch (direction) {
      case 'up':    sx = cx; sy = cy - dist ~/ 2; ex = cx; ey = cy + dist ~/ 2;
      case 'down':  sx = cx; sy = cy + dist ~/ 2; ex = cx; ey = cy - dist ~/ 2;
      case 'left':  sx = cx - dist ~/ 2; sy = cy; ex = cx + dist ~/ 2; ey = cy;
      case 'right': sx = cx + dist ~/ 2; sy = cy; ex = cx - dist ~/ 2; ey = cy;
      default:      sx = cx; sy = cy + dist ~/ 2; ex = cx; ey = cy - dist ~/ 2;
    }
    try {
      await adbShell('input swipe $sx $sy $ex $ey 300');
      return ToolResult.ok('Scrolled $direction via ADB');
    } catch (e) {
      return ToolResult.err('ADB scroll failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// ADB Long Press
// ════════════════════════════════════════════

class AdbLongPressTool extends KoloTool {
  @override String get name => 'long_press';
  @override String get description => 'Long press at coordinates via ADB (uses swipe with same start/end).';
  @override Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'x': {'type': 'number'},
      'y': {'type': 'number'},
      'duration': {'type': 'integer', 'description': 'Duration in ms (default 500)'},
    },
    'required': ['x', 'y'],
  };
  @override ToolPermission get permission => ToolPermission.dangerous;
  @override ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final x = (params['x'] as num).toInt();
    final y = (params['y'] as num).toInt();
    final dur = params['duration'] as int? ?? 500;
    try {
      // ADB long-press trick: swipe from same point to same point with long duration
      await adbShell('input swipe $x $y $x $y $dur');
      return ToolResult.ok('Long pressed at ($x, $y) for ${dur}ms via ADB');
    } catch (e) {
      return ToolResult.err('ADB long press failed: $e');
    }
  }
}
