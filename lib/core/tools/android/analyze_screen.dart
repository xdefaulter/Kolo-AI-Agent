import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tool_base.dart';
import '../../storage/database.dart';
import '../../api/provider.dart';
import 'phone_controller.dart';
import 'vlm_analyzer.dart';

/// Tool: Analyze screen with Vision model
/// Takes screenshot → sends to VLM → gets back actions → optionally executes them
class AnalyzeScreenTool extends KoloTool {
  final WidgetRef? ref;

  AnalyzeScreenTool({this.ref});

  @override
  String get name => 'analyze_screen';
  @override
  String get description => 'Take a screenshot and analyze it with a vision model. The VLM will suggest what actions to take on the screen. Returns the suggested actions. Use this when the accessibility tree alone isn\'t enough to understand the screen.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'task': {'type': 'string', 'description': 'What you are trying to accomplish on the screen'},
      'include_tree': {'type': 'boolean', 'description': 'Also include accessibility tree for better accuracy (default true)'},
      'execute': {'type': 'boolean', 'description': 'Automatically execute the suggested actions (default false). If false, just returns the plan.'},
    },
    'required': ['task'],
  };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final task = params['task'] as String;
    final includeTree = params['include_tree'] as bool? ?? true;
    final autoExecute = params['execute'] as bool? ?? false;

    // 1. Take screenshot
    const channel = MethodChannel('com.kolo.ai/phone_control');
    String? screenshotBase64;
    try {
      screenshotBase64 = await channel.invokeMethod<String>('takeScreenshot');
    } catch (e) {
      return ToolResult.err('Screenshot failed: $e. Start controller with phone_start first.');
    }
    if (screenshotBase64 == null) {
      return ToolResult.err('No screenshot captured. Make sure controller is started.');
    }

    // 2. Optionally get accessibility tree
    String? screenTree;
    if (includeTree) {
      try {
        screenTree = await channel.invokeMethod<String>('readScreen');
        if (screenTree != null && screenTree.length > 8000) {
          screenTree = screenTree.substring(0, 8000);
        }
      } catch (_) {}
    }

    // 3. Get VLM provider — if ref is null, try to build from database directly
    ApiProvider? visionProvider;
    if (ref != null) {
      visionProvider = await VlmScreenAnalyzer.buildVisionProvider(ref!);
    }
    
    // Fallback: try building provider from database without WidgetRef
    if (visionProvider == null) {
      try {
        final db = AppDatabase.instance;
        final activeProvider = await db.getActiveProvider();
        if (activeProvider != null && activeProvider.activeModel != null) {
          visionProvider = ApiProvider(
            id: activeProvider.id,
            name: activeProvider.name,
            baseUrl: activeProvider.baseUrl,
            apiKey: activeProvider.apiKey,
            model: activeProvider.activeModel!.modelId,
            customHeaders: activeProvider.customHeaders,
            maxTokens: 1024,
            temperature: 0.1,
          );
        }
      } catch (_) {}
    }

    if (visionProvider == null) {
      // Can't do VLM analysis, but still provide the screenshot data
      // that the agent LLM can use if it supports vision
      return ToolResult.ok(
        'Screenshot taken (${screenshotBase64.length} chars). '
        'No vision model configured for analysis. '
        'Go to Settings → Vision Model to set one up.\n\n'
        'Tip: Use screen_read tool for accessibility tree-based analysis instead.',
        metadata: {
          'image_base64': screenshotBase64,
          'format': 'jpeg',
        },
      );
    }

    // 4. Analyze with VLM
    final analyzer = VlmScreenAnalyzer(visionProvider);
    final result = await analyzer.analyze(
      screenshotBase64: screenshotBase64,
      taskDescription: task,
      screenTree: screenTree,
    );

    if (result.hasError) {
      return ToolResult.err('VLM analysis failed: ${result.error}');
    }

    if (result.needsInterpretation) {
      return ToolResult.ok('VLM response (no structured actions found):\n${result.rawContent}\n\nUse this info with tap/swipe/type_text tools manually.');
    }

    if (result.actions.isEmpty) {
      return ToolResult.ok('VLM returned no actions. The screen may already show the desired state, or the model couldn\'t determine what to do.');
    }

    if (result.isDone) {
      return ToolResult.ok('VLM indicates the task is complete. No further actions needed.');
    }

    // Build action summary
    final actionSummary = result.actions.map((a) {
      final action = a['action'];
      switch (action) {
        case 'tap': return 'tap(${a['x']}, ${a['y']})';
        case 'long_press': return 'long_press(${a['x']}, ${a['y']}, ${a['duration_ms'] ?? 500}ms)';
        case 'swipe': return 'swipe(${a['startX']},${a['startY']} → ${a['endX']},${a['endY']})';
        case 'type_text': return 'type_text("${a['text']}")';
        case 'press_key': return 'press_key(${a['key']})';
        case 'scroll': return 'scroll(${a['direction']})';
        case 'click_text': return 'click_text("${a['text']}")';
        default: return '$action($a)';
      }
    }).join('\n → ');

    if (!autoExecute) {
      return ToolResult.ok('Suggested actions (not executed — pass execute:true to auto-run):\n → $actionSummary\n\nRaw: ${result.rawContent}');
    }

    // 5. Auto-execute actions
    final executed = <String>[];
    for (final action in result.actions) {
      final actionType = action['action'] as String;
      String outcome;

      try {
        switch (actionType) {
          case 'tap':
            await channel.invokeMethod<bool>('tap', {'x': action['x'], 'y': action['y']});
            outcome = '✓ tap(${action['x']}, ${action['y']})';
            await Future.delayed(const Duration(milliseconds: 300));
          case 'long_press':
            await channel.invokeMethod<bool>('longPress', {
              'x': action['x'], 'y': action['y'],
              'duration': action['duration_ms'] ?? 500,
            });
            outcome = '✓ long_press(${action['x']}, ${action['y']})';
            await Future.delayed(const Duration(milliseconds: 300));
          case 'swipe':
            await channel.invokeMethod<bool>('swipe', {
              'startX': action['startX'], 'startY': action['startY'],
              'endX': action['endX'], 'endY': action['endY'],
              'duration': action['duration_ms'] ?? 300,
            });
            outcome = '✓ swipe';
            await Future.delayed(const Duration(milliseconds: 500));
          case 'type_text':
            await channel.invokeMethod<bool>('typeText', {'text': action['text']});
            outcome = '✓ type_text("${action['text']}")';
            await Future.delayed(const Duration(milliseconds: 200));
          case 'press_key':
            await channel.invokeMethod<bool>('pressKey', {'key': action['key']});
            outcome = '✓ press_key(${action['key']})';
            await Future.delayed(const Duration(milliseconds: 500));
          case 'scroll':
            await channel.invokeMethod<bool>('scroll', {'direction': action['direction'] ?? 'down'});
            outcome = '✓ scroll(${action['direction']})';
            await Future.delayed(const Duration(milliseconds: 500));
          case 'click_text':
            await channel.invokeMethod<bool>('clickByText', {'text': action['text']});
            outcome = '✓ click_text("${action['text']}")';
            await Future.delayed(const Duration(milliseconds: 300));
          default:
            outcome = '⚠ Unknown action: $actionType';
        }
      } catch (e) {
        outcome = '✗ $actionType failed: $e';
      }
      executed.add(outcome);
    }

    return ToolResult.ok('Executed ${executed.length} actions:\n${executed.join('\n')}\n\nVLM reasoning: ${result.rawContent}');
  }
}