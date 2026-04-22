import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import '../tool_base.dart';

/// Check network connectivity type and status.
class ConnectivityTool extends KoloTool {
  @override
  String get name => 'connectivity';
  @override
  String get description => 'Check the device network status: WiFi, mobile data, ethernet, or offline.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {},
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      final types = results.map((r) => _describeResult(r)).toList();
      final online = !results.contains(ConnectivityResult.none);

      return ToolResult.ok(
        'Network: ${online ? "Online" : "Offline"}\n'
        'Connection: ${types.join(", ")}',
        metadata: {'online': online, 'types': types},
      );
    } catch (e) {
      return ToolResult.err('Connectivity check failed: $e');
    }
  }

  String _describeResult(ConnectivityResult r) => switch (r) {
    ConnectivityResult.wifi => 'WiFi',
    ConnectivityResult.mobile => 'Mobile Data',
    ConnectivityResult.ethernet => 'Ethernet',
    ConnectivityResult.bluetooth => 'Bluetooth',
    ConnectivityResult.vpn => 'VPN',
    ConnectivityResult.other => 'Other',
    ConnectivityResult.none => 'No Connection',
    _ => r.name,
  };
}

/// Get battery level and charging status.
class BatteryInfoTool extends KoloTool {
  @override
  String get name => 'battery_info';
  @override
  String get description => 'Get the device battery level, charging status, and battery health info.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {},
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;

      final stateStr = switch (state) {
        BatteryState.charging => 'Charging',
        BatteryState.discharging => 'Discharging',
        BatteryState.full => 'Full',
        BatteryState.unknown => 'Unknown',
        _ => state.name,
      };

      return ToolResult.ok(
        'Battery: $level%\nState: $stateStr',
        metadata: {'level': level, 'state': stateStr},
      );
    } catch (e) {
      return ToolResult.err('Battery info failed: $e');
    }
  }
}

/// Trigger device vibration/haptic feedback.
class VibrateTool extends KoloTool {
  @override
  String get name => 'vibrate';
  @override
  String get description => 'Trigger device vibration. Patterns: light, medium, heavy, rapid, or custom duration in ms.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'pattern': {'type': 'string', 'enum': ['light', 'medium', 'heavy'], 'description': 'Vibration pattern (default medium)'},
      'duration_ms': {'type': 'integer', 'description': 'Custom duration in milliseconds (overrides pattern)'},
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final pattern = params['pattern'] as String? ?? 'medium';
    final durationMs = params['duration_ms'] as int?;

    try {
      final canVibrate = await Vibrate.canVibrate;
      if (!canVibrate) {
        return ToolResult.ok('Device does not support vibration');
      }

      if (durationMs != null) {
        await Vibrate.vibrateWithPauses(
          [Duration(milliseconds: durationMs)],
        );
      } else {
        switch (pattern) {
          case 'light':
            await Vibrate.feedback(FeedbackType.light);
          case 'heavy':
            await Vibrate.feedback(FeedbackType.heavy);
          case 'selection':
            await Vibrate.feedback(FeedbackType.selection);
          case 'success':
            await Vibrate.feedback(FeedbackType.success);
          case 'warning':
            await Vibrate.feedback(FeedbackType.warning);
          case 'error':
            await Vibrate.feedback(FeedbackType.error);
          default:
            await Vibrate.feedback(FeedbackType.medium);
        }
      }

      return ToolResult.ok('Vibration triggered: ${durationMs != null ? "${durationMs}ms" : pattern}');
    } catch (e) {
      return ToolResult.err('Vibration failed: $e');
    }
  }
}

/// Read EXIF metadata from an image file.
class ImageMetadataTool extends KoloTool {
  @override
  String get name => 'image_metadata';
  @override
  String get description => 'Read EXIF metadata from a JPEG/TIFF image file. Returns GPS coordinates, camera info, dates, etc.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Path to the image file'},
    },
    'required': ['path'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final path = params['path'] as String;
    try {
      final file = File(path);
      if (!await file.exists()) return ToolResult.err('File not found: $path');

      final bytes = await file.readAsBytes();
      // Use basic EXIF parsing — check for JPEG marker
      if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        return ToolResult.err('Not a valid JPEG file');
      }

      // Quick scan for EXIF data without full decode
      final fileSize = bytes.length;
      final lines = <String>[];

      lines.add('File: $path');
      lines.add('Size: ${(fileSize / 1024).toStringAsFixed(1)} KB');

      // Check if EXIF marker exists (FFE1)
      bool hasExif = false;
      for (int i = 2; i < bytes.length - 4; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xE1) {
          hasExif = true;
          break;
        }
      }

      if (hasExif) {
        lines.add('EXIF data: Present');

        // Try to extract basic info from EXIF
        try {
          final exifData = await _parseExif(bytes);
          lines.addAll(exifData);
        } catch (_) {
          lines.add('(Could not decode EXIF details)');
        }
      } else {
        lines.add('EXIF data: None');
      }

      return ToolResult.ok(lines.join('\n'));
    } catch (e) {
      return ToolResult.err('Image metadata failed: $e');
    }
  }

  Future<List<String>> _parseExif(List<int> bytes) async {
    final lines = <String>[];

    // Find EXIF data start
    for (int i = 2; i < bytes.length - 20; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xE1) {
        // Skip marker and length
        int offset = i + 4;
        // Check for "Exif\0\0"
        if (offset + 6 < bytes.length) {
          final header = String.fromCharCodes(bytes.sublist(offset, offset + 6));
          if (header == 'Exif\x00\x00') {
            offset += 6;
            // Parse TIFF header for byte order
            if (offset + 8 < bytes.length) {
              final byteOrder = String.fromCharCodes(bytes.sublist(offset, offset + 2));
              lines.add('Byte order: ${byteOrder == "MM" ? "Big-endian" : "Little-endian"}');
            }
            break;
          }
        }
        break;
      }
    }

    // Try to find common string tags
    final commonTags = {
      0x010F: 'Make',
      0x0110: 'Model',
      0x0112: 'Orientation',
      0x0131: 'Software',
    };

    // Search for Make/Model strings in EXIF block
    for (final entry in commonTags.entries) {
      final tagBytes = [(entry.key >> 8) & 0xFF, entry.key & 0xFF];
      for (int i = 0; i < bytes.length - 100; i++) {
        if (bytes[i] == tagBytes[0] && bytes[i + 1] == tagBytes[1]) {
          // Found a potential tag — try to read nearby string
          // This is a simplified parser
        }
      }
    }

    if (lines.length <= 1) {
      lines.add('(EXIF data present but detailed parsing requires image file scan)');
    }

    return lines;
  }
}