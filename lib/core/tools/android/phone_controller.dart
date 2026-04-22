import 'package:flutter/services.dart';
import '../tool_base.dart';

/// MethodChannel for phone control
const _channel = MethodChannel('com.kolo.ai/phone_control');

// ════════════════════════════════════════════
// Tool: Start Phone Controller
// ════════════════════════════════════════════

class StartControllerTool extends KoloTool {
  @override
  String get name => 'phone_start';
  @override
  String get description => 'Start the phone controller (accessibility service + foreground service with overlays). Required before any other phone control tools can work. Will prompt for overlay & accessibility permissions if not granted.';
  @override
  Map<String, dynamic> get parameterSchema => {'type': 'object', 'properties': {}, 'required': []};
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      // Check overlay permission first so we can give a clear error
      final overlayGranted = await _channel.invokeMethod<bool>('isOverlayPermissionGranted') ?? false;
      if (!overlayGranted) {
        // Request overlay permission (opens system settings, user must toggle it on)
        await _channel.invokeMethod<bool>('requestOverlayPermission');
        // The user needs to manually grant it and come back, so tell them
        return ToolResult.err('Overlay permission needed. Settings page opened — enable "Display over other apps" for Kolo AI Agent, then try phone_start again.');
      }
      
      final result = await _channel.invokeMethod<dynamic>('startController');
      if (result == true) {
        return ToolResult.ok('Phone controller started. Accessibility ✓ | Foreground service ✓ | Overlays ✓');
      } else {
        return ToolResult.err('Failed to start controller');
      }
    } on PlatformException catch (e) {
      if (e.code == 'NO_ACCESSIBILITY') {
        return ToolResult.err('Accessibility not enabled. Opening settings — enable "Kolo AI Agent" in Accessibility, then try phone_start again.');
      }
      if (e.code == 'NO_OVERLAY') {
        return ToolResult.err('Overlay permission needed. Settings page opened — enable "Display over other apps" for Kolo AI Agent, then try phone_start again.');
      }
      return ToolResult.err('Start controller failed: ${e.message}');
    } catch (e) {
      return ToolResult.err('Start controller failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Stop Phone Controller
// ════════════════════════════════════════════

class StopControllerTool extends KoloTool {
  @override
  String get name => 'phone_stop';
  @override
  String get description => 'Stop the phone controller and remove all overlays (border, STOP button, action text).';
  @override
  Map<String, dynamic> get parameterSchema => {'type': 'object', 'properties': {}, 'required': []};
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      await _channel.invokeMethod<bool>('stopController');
      return ToolResult.ok('Phone controller stopped. All overlays removed.');
    } catch (e) {
      return ToolResult.err('Stop controller failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Read Screen (Accessibility Tree)
// ════════════════════════════════════════════

class ReadScreenTool extends KoloTool {
  @override
  String get name => 'screen_read';
  @override
  String get description => 'Read the current screen content via accessibility tree. Returns JSON with all visible UI elements: text, bounds, clickability, editability, etc.';
  @override
  Map<String, dynamic> get parameterSchema => {'type': 'object', 'properties': {}, 'required': []};
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      final tree = await _channel.invokeMethod<String>('readScreen');
      if (tree == null || tree == '[]') {
        return ToolResult.ok('Screen is empty or no accessible content found.');
      }
      if (tree.length > 15000) {
        return ToolResult.ok('Screen tree (truncated):\n${tree.substring(0, 15000)}...\n\n(${tree.length} chars total — use screenshot tool for full visual context)');
      }
      return ToolResult.ok('Screen content:\n$tree');
    } on PlatformException catch (e) {
      if (e.code == 'NO_SERVICE') {
        return ToolResult.err('Accessibility service not running. Use phone_start tool first.');
      }
      return ToolResult.err('Read screen failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Take Screenshot (via Accessibility, no screen recording)
// ════════════════════════════════════════════

class ScreenshotTool extends KoloTool {
  @override
  String get name => 'screenshot';
  @override
  String get description => 'Take a screenshot using AccessibilityService (no screen recording permission needed). Returns base64-encoded JPEG. Use with vision/analyze_screen tool to understand the screen visually.';
  @override
  Map<String, dynamic> get parameterSchema => {'type': 'object', 'properties': {}, 'required': []};
  @override
  ToolPermission get permission => ToolPermission.sensitive;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      final base64 = await _channel.invokeMethod<String>('takeScreenshot');
      if (base64 == null) {
        return ToolResult.err('Screenshot failed — no image captured. Make sure controller is started with phone_start.');
      }
      return ToolResult.ok('Screenshot captured (${base64.length} chars base64)', metadata: {
        'image_base64': base64,
        'format': 'jpeg',
      });
    } on PlatformException catch (e) {
      if (e.code == 'NO_SERVICE') {
        return ToolResult.err('Accessibility service not running. Use phone_start tool first.');
      }
      if (e.code == 'UNSUPPORTED') {
        return ToolResult.err('Screenshots require Android 11+ (API 30). Your device is too old.');
      }
      return ToolResult.err('Screenshot failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Show Action Overlay
// ════════════════════════════════════════════

class ShowActionTool extends KoloTool {
  @override
  String get name => 'show_action';
  @override
  String get description => 'Show a brief overlay text describing what the agent is doing (e.g. "Tapping Settings button"). Auto-hides after 3 seconds.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'Action description to display'},
    },
    'required': ['text'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final text = params['text'] as String;
    try {
      await _channel.invokeMethod<bool>('showAction', {'text': text});
      return ToolResult.ok('Action overlay shown: "$text"');
    } catch (e) {
      return ToolResult.err('Show action failed: $e');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Tap
// ════════════════════════════════════════════

class TapTool extends KoloTool {
  @override
  String get name => 'tap';
  @override
  String get description => 'Tap at specific screen coordinates (x, y). Use screen_read to find element bounds first.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'x': {'type': 'number', 'description': 'X coordinate (pixels from left)'},
      'y': {'type': 'number', 'description': 'Y coordinate (pixels from top)'},
    },
    'required': ['x', 'y'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final x = (params['x'] as num).toDouble();
    final y = (params['y'] as num).toDouble();
    try {
      final success = await _channel.invokeMethod<bool>('tap', {'x': x, 'y': y});
      return ToolResult.ok(success == true ? 'Tapped at ($x, $y)' : 'Tap failed at ($x, $y)');
    } on PlatformException catch (e) {
      return ToolResult.err('Tap failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Swipe
// ════════════════════════════════════════════

class SwipeTool extends KoloTool {
  @override
  String get name => 'swipe';
  @override
  String get description => 'Swipe from one point to another. Use for scrolling, swiping between pages, etc.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'startX': {'type': 'number', 'description': 'Start X coordinate'},
      'startY': {'type': 'number', 'description': 'Start Y coordinate'},
      'endX': {'type': 'number', 'description': 'End X coordinate'},
      'endY': {'type': 'number', 'description': 'End Y coordinate'},
      'duration': {'type': 'integer', 'description': 'Duration in milliseconds (default 300)'},
    },
    'required': ['startX', 'startY', 'endX', 'endY'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final startX = (params['startX'] as num).toDouble();
    final startY = (params['startY'] as num).toDouble();
    final endX = (params['endX'] as num).toDouble();
    final endY = (params['endY'] as num).toDouble();
    final duration = params['duration'] as int? ?? 300;
    try {
      final success = await _channel.invokeMethod<bool>('swipe', {
        'startX': startX, 'startY': startY,
        'endX': endX, 'endY': endY,
        'duration': duration,
      });
      return ToolResult.ok(success == true
        ? 'Swiped from ($startX,$startY) to ($endX,$endY) in ${duration}ms'
        : 'Swipe failed');
    } on PlatformException catch (e) {
      return ToolResult.err('Swipe failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Type Text
// ════════════════════════════════════════════

class TypeTextTool extends KoloTool {
  @override
  String get name => 'type_text';
  @override
  String get description => 'Type text into the currently focused input field. Tap on an input field first before typing.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'Text to type'},
    },
    'required': ['text'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final text = params['text'] as String;
    try {
      final success = await _channel.invokeMethod<bool>('typeText', {'text': text});
      return ToolResult.ok(success == true ? 'Typed: "$text"' : 'Type failed — no focused input field');
    } on PlatformException catch (e) {
      return ToolResult.err('Type failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Press Key
// ════════════════════════════════════════════

class PressKeyTool extends KoloTool {
  @override
  String get name => 'press_key';
  @override
  String get description => 'Press a system key: back, home, recents, notifications, quick_settings, power_dialog, lock_screen, enter.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'key': {'type': 'string', 'enum': ['back', 'home', 'recents', 'notifications', 'quick_settings', 'power_dialog', 'lock_screen', 'enter'], 'description': 'Key to press'},
    },
    'required': ['key'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final key = params['key'] as String;
    try {
      final success = await _channel.invokeMethod<bool>('pressKey', {'key': key});
      return ToolResult.ok(success == true ? 'Pressed $key' : 'Press $key failed');
    } on PlatformException catch (e) {
      return ToolResult.err('Press key failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Scroll
// ════════════════════════════════════════════

class ScrollTool extends KoloTool {
  @override
  String get name => 'scroll';
  @override
  String get description => 'Scroll the screen in a direction: up, down, left, right. Automatically finds the scrollable container.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right'], 'description': 'Scroll direction (default down)'},
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final direction = params['direction'] as String? ?? 'down';
    try {
      final success = await _channel.invokeMethod<bool>('scroll', {'direction': direction});
      return ToolResult.ok(success == true ? 'Scrolled $direction' : 'Scroll $direction failed — no scrollable container found');
    } on PlatformException catch (e) {
      return ToolResult.err('Scroll failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Click by Text
// ════════════════════════════════════════════

class ClickByTextTool extends KoloTool {
  @override
  String get name => 'click_text';
  @override
  String get description => 'Click a UI element matching the given text. Searches accessibility tree for elements containing the text and clicks the first match.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'Text to search for (partial match)'},
    },
    'required': ['text'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final text = params['text'] as String;
    try {
      final success = await _channel.invokeMethod<bool>('clickByText', {'text': text});
      return ToolResult.ok(success == true ? 'Clicked element with text "$text"' : 'No clickable element found with text "$text"');
    } on PlatformException catch (e) {
      return ToolResult.err('Click by text failed: ${e.message}');
    }
  }
}

// ════════════════════════════════════════════
// Tool: Long Press
// ════════════════════════════════════════════

class LongPressTool extends KoloTool {
  @override
  String get name => 'long_press';
  @override
  String get description => 'Long press at specific screen coordinates.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'x': {'type': 'number', 'description': 'X coordinate'},
      'y': {'type': 'number', 'description': 'Y coordinate'},
      'duration': {'type': 'integer', 'description': 'Duration in milliseconds (default 500)'},
    },
    'required': ['x', 'y'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final x = (params['x'] as num).toDouble();
    final y = (params['y'] as num).toDouble();
    final duration = params['duration'] as int? ?? 500;
    try {
      final success = await _channel.invokeMethod<bool>('longPress', {'x': x, 'y': y, 'duration': duration});
      return ToolResult.ok(success == true ? 'Long pressed at ($x, $y) for ${duration}ms' : 'Long press failed');
    } on PlatformException catch (e) {
      return ToolResult.err('Long press failed: ${e.message}');
    }
  }
}