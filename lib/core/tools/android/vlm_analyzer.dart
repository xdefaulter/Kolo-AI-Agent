import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/provider.dart';
import '../../storage/database.dart';
import 'phone_controller.dart';

/// Vision model settings — persisted
enum VisionModelMode {
  sameAsChat,    // Use the same provider+model as chat
  separate,      // Use a different provider+model for vision
}

/// State: vision model config
class VisionModelConfig {
  final VisionModelMode mode;
  final String? providerId;  // Only used when mode == separate
  final String? modelId;     // Only used when mode == separate

  VisionModelConfig({
    this.mode = VisionModelMode.sameAsChat,
    this.providerId,
    this.modelId,
  });

  Map<String, dynamic> toMap() => {
    'mode': mode.name,
    'providerId': providerId,
    'modelId': modelId,
  };

  factory VisionModelConfig.fromMap(Map<String, dynamic> m) => VisionModelConfig(
    mode: VisionModelMode.values.firstWhere(
      (v) => v.name == m['mode'],
      orElse: () => VisionModelMode.sameAsChat,
    ),
    providerId: m['providerId'] as String?,
    modelId: m['modelId'] as String?,
  );
}

/// Riverpod provider for vision model config
final visionModelConfigProvider = StateNotifierProvider<VisionModelConfigNotifier, VisionModelConfig>((ref) {
  return VisionModelConfigNotifier();
});

class VisionModelConfigNotifier extends StateNotifier<VisionModelConfig> {
  VisionModelConfigNotifier() : super(VisionModelConfig()) {
    _load();
  }

  Future<void> _load() async {
    final db = AppDatabase.instance;
    final saved = await db.getSetting('vision_model_config');
    if (saved != null) {
      try {
        state = VisionModelConfig.fromMap(jsonDecode(saved) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> update(VisionModelConfig config) async {
    state = config;
    final db = AppDatabase.instance;
    await db.saveSetting('vision_model_config', jsonEncode(config.toMap()));
  }
}

/// VLM Screen Analyzer — sends screenshot to vision model and gets back actions
class VlmScreenAnalyzer {
  final ApiProvider visionProvider;

  VlmScreenAnalyzer(this.visionProvider);

  /// Analyze a screenshot and return suggested actions.
  /// [screenshotBase64] — JPEG base64 of current screen
  /// [taskDescription] — what the agent is trying to accomplish
  /// [screenTree] — optional accessibility tree text for additional context
  Future<VlmAnalysisResult> analyze({
    required String screenshotBase64,
    required String taskDescription,
    String? screenTree,
  }) async {
    final dio = Dio(BaseOptions(
      baseUrl: visionProvider.baseUrl,
      headers: {
        'Authorization': 'Bearer ${visionProvider.apiKey}',
        'Content-Type': 'application/json',
        ...visionProvider.customHeaders,
      },
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      validateStatus: (status) => true,
    ));

    // Build the vision message
    final systemPrompt = '''You are a phone automation assistant. You analyze screenshots of an Android phone screen and decide what actions to take to accomplish the user's task.

Available actions:
- tap(x, y) — tap at coordinates
- long_press(x, y, duration_ms) — long press
- swipe(startX, startY, endX, endY, duration_ms) — swipe gesture
- type_text(text) — type text into focused input
- press_key(key) — system key: back, home, recents, notifications, enter
- scroll(direction) — scroll up, down, left, right
- click_text(text) — click element containing text
- done — task is complete, stop

IMPORTANT: Respond ONLY with a JSON array of actions. Each action is an object with "action" and parameters.
Example: [{"action": "tap", "x": 540, "y": 1200}, {"action": "type_text", "text": "hello"}]

If the task is already complete, respond: [{"action": "done"}]''';

    final userContent = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': 'Task: $taskDescription\n\nAnalyze this screenshot and determine the next action(s) to take.${screenTree != null ? '\n\nAdditional context from accessibility tree (use coordinates from bounds):\n$screenTree' : ''}',
      },
      {
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/jpeg;base64,$screenshotBase64',
        },
      },
    ];

    final requestBody = {
      'model': visionProvider.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
      'max_tokens': 1024,
      'temperature': 0.1,
    };

    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/chat/completions',
        data: requestBody,
      );

      if (response.statusCode != null && response.statusCode! >= 400) {
        final body = response.data;
        String detail = '';
        if (body != null && body['error'] is Map) {
          detail = (body['error'] as Map?)?['message']?.toString() ?? body.toString();
        }
        return VlmAnalysisResult(error: 'HTTP ${response.statusCode}: $detail');
      }

      final data = response.data;
      if (data == null) return VlmAnalysisResult(error: 'No response data');

      final content = (data['choices'] as List?)?[0]?['message']?['content'] as String? ?? '';
      return _parseActions(content);
    } catch (e) {
      return VlmAnalysisResult(error: 'VLM request failed: $e');
    }
  }

  VlmAnalysisResult _parseActions(String content) {
    // Try to extract JSON from the response
    try {
      // Find JSON array in the response
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final actions = jsonDecode(jsonStr) as List;
        final parsed = actions.map((a) => Map<String, dynamic>.from(a as Map)).toList();
        return VlmAnalysisResult(actions: parsed, rawContent: content);
      }
    } catch (_) {}

    // No JSON found — return the raw content as a text observation
    return VlmAnalysisResult(actions: [], rawContent: content, needsInterpretation: true);
  }

  /// Build a vision-capable ApiProvider from the current settings
  static Future<ApiProvider?> buildVisionProvider(WidgetRef ref) async {
    final config = ref.read(visionModelConfigProvider);
    final db = AppDatabase.instance;

    if (config.mode == VisionModelMode.sameAsChat) {
      // Use the same active provider+model
      final activeProvider = await db.getActiveProvider();
      if (activeProvider == null) return null;
      final activeModel = activeProvider.activeModel;
      return ApiProvider(
        id: activeProvider.id,
        name: activeProvider.name,
        baseUrl: activeProvider.baseUrl,
        apiKey: activeProvider.apiKey,
        model: activeModel?.modelId ?? 'gpt-4o',
        customHeaders: activeProvider.customHeaders,
        maxTokens: 1024,
        temperature: 0.1,
      );
    } else {
      // Use the configured separate vision provider
      if (config.providerId == null) return null;
      final providers = await db.getAllProviders();
      final provider = providers.where((p) => p.id == config.providerId).firstOrNull;
      if (provider == null) return null;
      return ApiProvider(
        id: provider.id,
        name: provider.name,
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: config.modelId ?? provider.activeModel?.modelId ?? 'gpt-4o',
        customHeaders: provider.customHeaders,
        maxTokens: 1024,
        temperature: 0.1,
      );
    }
  }
}

class VlmAnalysisResult {
  final List<Map<String, dynamic>> actions;
  final String rawContent;
  final bool needsInterpretation;
  final String? error;

  VlmAnalysisResult({
    this.actions = const [],
    this.rawContent = '',
    this.needsInterpretation = false,
    this.error,
  });

  bool get hasError => error != null;
  bool get isDone => actions.any((a) => a['action'] == 'done');
}