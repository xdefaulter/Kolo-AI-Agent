import 'package:flutter/services.dart';
import '../tool_base.dart';

const _channel = MethodChannel('com.kolo.ai/phone_control');

/// Tool: Start Phone Control Mode
/// Shows persistent border, STOP button, and status overlay.
/// The agent calls this at the beginning of a phone task sequence.
class PhoneControlStartTool extends KoloTool {
  @override
  String get name => 'phone_control_start';
  @override
  String get description =>
      'Start phone control mode. Call this ONCE at the beginning when you are about to perform a series of phone actions (opening apps, tapping, reading screens). '
      'This shows a persistent border, STOP button, and status overlay so the user knows the agent is controlling the phone. '
      'Call phone_control_done when finished to dismiss the overlay.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'task': {'type': 'string', 'description': 'Short description of what you\'re about to do (e.g. "Ordering coffee on Starbucks")'},
    },
    'required': ['task'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final task = params['task'] as String;
    try {
      await _channel.invokeMethod<bool>('phoneControlStart', {'task': task});
      return ToolResult.ok('Phone control mode started. Border and STOP button visible. Task: "$task"');
    } catch (e) {
      // Fallback: if phone_start hasn't been called yet, try starting controller first
      try {
        await _channel.invokeMethod<bool>('startController');
        await _channel.invokeMethod<bool>('phoneControlStart', {'task': task});
        return ToolResult.ok('Phone control mode started. Border and STOP button visible. Task: "$task"');
      } catch (e2) {
        return ToolResult.err('Failed to start phone control mode: $e2. Try phone_start first.');
      }
    }
  }
}

/// Tool: End Phone Control Mode
/// Hides the persistent border, STOP button, and status overlay.
/// The agent calls this when done with phone tasks.
class PhoneControlDoneTool extends KoloTool {
  @override
  String get name => 'phone_control_done';
  @override
  String get description =>
      'End phone control mode. Call this when you are finished with phone actions to dismiss the border, STOP button, and status overlay.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'summary': {'type': 'string', 'description': 'Brief summary of what was accomplished (shown briefly before overlay disappears)'},
    },
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final summary = params['summary'] as String? ?? '';
    try {
      await _channel.invokeMethod<bool>('phoneControlDone', {'summary': summary});
      return ToolResult.ok(summary.isNotEmpty
        ? 'Phone control mode ended. $summary'
        : 'Phone control mode ended. Overlays dismissed.');
    } catch (e) {
      return ToolResult.err('Failed to end phone control mode: $e');
    }
  }
}

/// Tool: Update Phone Control Status
/// Updates the status text shown in the overlay during phone control mode.
class PhoneControlStatusTool extends KoloTool {
  @override
  String get name => 'phone_control_status';
  @override
  String get description =>
      'Update the status text shown in the phone control overlay. Use this to show what you\'re currently doing (e.g. "Opening Starbucks", "Searching for menu"). '
      'Only works while phone control mode is active (after phone_control_start).';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'status': {'type': 'string', 'description': 'Current action status to display'},
    },
    'required': ['status'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final status = params['status'] as String;
    try {
      await _channel.invokeMethod<bool>('phoneControlStatus', {'status': status});
      return ToolResult.ok('Status updated: "$status"');
    } catch (e) {
      return ToolResult.err('Failed to update status: $e');
    }
  }
}