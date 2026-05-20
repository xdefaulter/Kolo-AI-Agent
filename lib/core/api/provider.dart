import 'package:uuid/uuid.dart';

/// How a provider delivers completions. Determines which client the
/// agent session spins up — OpenAI-compatible HTTP vs on-device llama.cpp
/// FFI — without either side needing to know about the other.
enum ProviderKind {
  /// Any HTTP backend that speaks OpenAI's /v1/chat/completions dialect.
  /// Covers OpenAI, Groq, OpenRouter, Fireworks, Together, Ollama, and
  /// most self-hosted inference servers.
  openaiCompat,

  /// On-device inference via a bundled llama.cpp binding. `modelPath`
  /// points at a .gguf file in app-private storage; no network at all.
  localLlama;

  String get wire {
    switch (this) {
      case ProviderKind.openaiCompat:
        return 'openai';
      case ProviderKind.localLlama:
        return 'local-llama';
    }
  }

  static ProviderKind fromWire(String? raw) {
    switch (raw) {
      case 'local-llama':
        return ProviderKind.localLlama;
      case 'openai':
      default:
        return ProviderKind.openaiCompat;
    }
  }
}

/// Lightweight provider config passed to OpenAIClient.
/// Created from a ProviderConfig + selected ModelConfig.
class ApiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final Map<String, String> customHeaders;
  final int maxTokens;
  final double temperature;
  final bool isActive;

  /// Provider kind copied from the parent ProviderConfig. Downstream
  /// clients dispatch on this so `AgentSession` never hard-codes which
  /// network client to use.
  final ProviderKind kind;

  /// Absolute path to a local GGUF file. Required when [kind] is
  /// `localLlama`; ignored for `openaiCompat`.
  final String? modelPath;

  /// Tools the agent must NOT call while using this provider. Small
  /// local models tend to hallucinate into complex tool schemas; this
  /// list lets the user shrink the tool surface per-provider without
  /// disabling the tool globally.
  final Set<String> disabledTools;

  ApiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.customHeaders = const {},
    this.maxTokens = 4096,
    this.temperature = 0.7,
    this.isActive = true,
    this.kind = ProviderKind.openaiCompat,
    this.modelPath,
    this.disabledTools = const {},
  });
}

/// An API provider endpoint connection.
/// Each provider has a base URL, auth, and can host multiple models.
class ProviderConfig {
  final String id;
  String name;
  String baseUrl;           // e.g. "https://api.openai.com/v1"
  String apiKey;
  Map<String, String> customHeaders;
  bool isActive;            // currently selected provider
  String? modelsEndpoint;   // e.g. "https://ollama.local:11434/v1/models" — null if not supported
  DateTime createdAt;
  DateTime updatedAt;

  /// Delivery mechanism (HTTP OAI vs on-device llama.cpp). Drives which
  /// client `AgentSession` spins up for this provider.
  ProviderKind kind;

  /// Absolute path to a local GGUF model file. Only meaningful when
  /// [kind] is [ProviderKind.localLlama]. Settable after creation so
  /// the HF-download flow can fill it in.
  String? modelPath;

  /// Tools this provider is NOT allowed to call. Checked in addition to
  /// the global per-tool permission gate — useful for small local models
  /// that can't reliably format complex tool schemas.
  Set<String> disabledTools;

  /// Opt-in "safe-by-default for a small local model" preset. When true,
  /// the agent session auto-hides any tool whose permission is
  /// `dangerous` (plus composed / meta tools) on top of [disabledTools].
  /// User can still toggle individual entries back on.
  bool smallModelMode;

  /// Models available under this provider
  List<ModelConfig> models;

  ProviderConfig({
    String? id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.customHeaders = const {},
    this.isActive = false,
    this.modelsEndpoint,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ModelConfig>? models,
    this.kind = ProviderKind.openaiCompat,
    this.modelPath,
    Set<String>? disabledTools,
    this.smallModelMode = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        models = models ?? [],
        disabledTools = disabledTools ?? <String>{};

  /// Whether this is a local/self-hosted provider (no API key needed)
  bool get isLocal => apiKey.isEmpty;

  /// Whether this provider supports fetching models dynamically
  bool get canFetchModels => modelsEndpoint != null && modelsEndpoint!.isNotEmpty;

  /// Build the models endpoint URL. If modelsEndpoint is set, use it.
  /// Otherwise, derive from baseUrl: baseUrl + "/models"
  String get effectiveModelsUrl {
    if (modelsEndpoint != null && modelsEndpoint!.isNotEmpty) return modelsEndpoint!;
    // Derive from baseUrl — ensure no double slash
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base/models';
  }

  /// Get the currently selected model (first active, or first model, or null)
  /// 9.3: Use null-safe lookup instead of try/catch for flow control.
  ModelConfig? get activeModel {
    final active = models.where((m) => m.isActive).firstOrNull;
    return active ?? (models.isNotEmpty ? models.first : null);
  }

  ProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    Map<String, String>? customHeaders,
    bool? isActive,
    String? modelsEndpoint,
    List<ModelConfig>? models,
    ProviderKind? kind,
    String? modelPath,
    Set<String>? disabledTools,
    bool? smallModelMode,
  }) {
    return ProviderConfig(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      customHeaders: customHeaders ?? this.customHeaders,
      isActive: isActive ?? this.isActive,
      modelsEndpoint: modelsEndpoint ?? this.modelsEndpoint,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      models: models ?? this.models,
      kind: kind ?? this.kind,
      modelPath: modelPath ?? this.modelPath,
      disabledTools: disabledTools ?? this.disabledTools,
      smallModelMode: smallModelMode ?? this.smallModelMode,
    );
  }

  /// Serialize to map including API key (used for in-memory transport only).
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'customHeaders': customHeaders,
        'isActive': isActive,
        'modelsEndpoint': modelsEndpoint,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'models': models.map((m) => m.toMap()).toList(),
        'kind': kind.wire,
        'modelPath': modelPath,
        'disabledTools': disabledTools.toList(),
        'smallModelMode': smallModelMode,
      };

  /// Serialize without API key — for SharedPreferences persistence.
  /// API keys are stored separately in flutter_secure_storage.
  Map<String, dynamic> toMapWithoutApiKey() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': '', // stored in secure storage
        'customHeaders': customHeaders,
        'isActive': isActive,
        'modelsEndpoint': modelsEndpoint,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'models': models.map((m) => m.toMap()).toList(),
        'kind': kind.wire,
        'modelPath': modelPath,
        'disabledTools': disabledTools.toList(),
        'smallModelMode': smallModelMode,
      };

  factory ProviderConfig.fromMap(Map<String, dynamic> m) => ProviderConfig(
        id: m['id'] as String,
        name: m['name'] as String,
        baseUrl: m['baseUrl'] as String,
        apiKey: m['apiKey'] as String? ?? '',
        customHeaders: Map<String, String>.from(m['customHeaders'] ?? {}),
        isActive: m['isActive'] as bool? ?? false,
        modelsEndpoint: m['modelsEndpoint'] as String?,
        createdAt: m['createdAt'] != null ? DateTime.parse(m['createdAt'] as String) : DateTime.now(),
        updatedAt: m['updatedAt'] != null ? DateTime.parse(m['updatedAt'] as String) : DateTime.now(),
        models: (m['models'] as List<dynamic>?)
                ?.map((e) => ModelConfig.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
        kind: ProviderKind.fromWire(m['kind'] as String?),
        modelPath: m['modelPath'] as String?,
        disabledTools: (m['disabledTools'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet() ??
            <String>{},
        smallModelMode: m['smallModelMode'] as bool? ?? false,
      );
}

/// A model within a provider. One provider can have many models.
/// E.g. OpenAI provider → gpt-4o, gpt-4o-mini, o1, etc.
class ModelConfig {
  final String id;
  String modelId;           // The model ID sent in API requests (e.g. "gpt-4o")
  String? displayName;      // Human-friendly name (e.g. "GPT-4o")
  int maxTokens;            // Max tokens for completions
  double temperature;       // Default temperature
  int? contextWindow;       // Context window size (tokens), if known
  bool isActive;            // Currently selected model within this provider
  bool isCustom;            // Manually added (not fetched from /models)
  String? description;      // E.g. "Most capable model"

  ModelConfig({
    String? id,
    required this.modelId,
    this.displayName,
    this.maxTokens = 4096,
    this.temperature = 0.7,
    this.contextWindow,
    this.isActive = false,
    this.isCustom = false,
    this.description,
  }) : id = id ?? const Uuid().v4();

  String get label => displayName ?? modelId;

  ModelConfig copyWith({
    String? modelId,
    String? displayName,
    int? maxTokens,
    double? temperature,
    int? contextWindow,
    bool? isActive,
    bool? isCustom,
    String? description,
  }) {
    return ModelConfig(
      id: id,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      contextWindow: contextWindow ?? this.contextWindow,
      isActive: isActive ?? this.isActive,
      isCustom: isCustom ?? this.isCustom,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'modelId': modelId,
        'displayName': displayName,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'contextWindow': contextWindow,
        'isActive': isActive,
        'isCustom': isCustom,
        'description': description,
      };

  factory ModelConfig.fromMap(Map<String, dynamic> m) => ModelConfig(
        id: m['id'] as String?,
        modelId: m['modelId'] as String,
        displayName: m['displayName'] as String?,
        maxTokens: m['maxTokens'] as int? ?? 4096,
        temperature: (m['temperature'] as num?)?.toDouble() ?? 0.7,
        contextWindow: m['contextWindow'] as int?,
        isActive: m['isActive'] as bool? ?? false,
        isCustom: m['isCustom'] as bool? ?? false,
        description: m['description'] as String?,
      );
}

/// Well-known provider presets for quick setup
class ProviderPresets {
  static List<ProviderConfig> get defaults => [
        ProviderConfig(
          name: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          modelsEndpoint: 'https://api.openai.com/v1/models',
          models: [
            ModelConfig(modelId: 'gpt-4o', displayName: 'GPT-4o', maxTokens: 4096, contextWindow: 128000, description: 'Most capable GPT-4 model'),
            ModelConfig(modelId: 'gpt-4o-mini', displayName: 'GPT-4o Mini', maxTokens: 4096, contextWindow: 128000, description: 'Fast and affordable'),
            ModelConfig(modelId: 'o1', displayName: 'o1', maxTokens: 4096, contextWindow: 200000, description: 'Reasoning model'),
            ModelConfig(modelId: 'o1-mini', displayName: 'o1 Mini', maxTokens: 4096, contextWindow: 128000, description: 'Fast reasoning'),
          ],
        ),
        ProviderConfig(
          name: 'Ollama (Local)',
          baseUrl: 'http://localhost:11434/v1',
          modelsEndpoint: 'http://localhost:11434/v1/models',
          models: [
            ModelConfig(modelId: 'llama3.2', displayName: 'Llama 3.2', maxTokens: 4096, contextWindow: 128000),
          ],
        ),
        ProviderConfig(
          name: 'Groq',
          baseUrl: 'https://api.groq.com/openai/v1',
          modelsEndpoint: 'https://api.groq.com/openai/v1/models',
          models: [
            ModelConfig(modelId: 'llama-3.3-70b-versatile', displayName: 'Llama 3.3 70B', maxTokens: 4096),
          ],
        ),
        // NOTE: Anthropic's API is NOT OpenAI-compatible (different message format, auth, streaming).
        // Use OpenRouter to access Claude/Gemini/etc via OpenAI-compatible API.
        ProviderConfig(
          name: 'OpenRouter',
          baseUrl: 'https://openrouter.ai/api/v1',
          modelsEndpoint: 'https://openrouter.ai/api/v1/models',
          models: [
            ModelConfig(modelId: 'anthropic/claude-sonnet-4-20250514', displayName: 'Claude Sonnet 4', maxTokens: 4096, contextWindow: 200000),
            ModelConfig(modelId: 'google/gemini-2.5-pro', displayName: 'Gemini 2.5 Pro', maxTokens: 4096, contextWindow: 1000000),
          ],
        ),
        ProviderConfig(
          name: 'Fireworks AI',
          baseUrl: 'https://api.fireworks.ai/inference/v1',
          modelsEndpoint: 'https://api.fireworks.ai/inference/v1/models',
          models: [
            ModelConfig(modelId: 'accounts/fireworks/models/llama-v3p3-70b-instruct', displayName: 'Llama 3.3 70B', maxTokens: 4096),
          ],
        ),
        ProviderConfig(
          name: 'Together AI',
          baseUrl: 'https://api.together.xyz/v1',
          modelsEndpoint: 'https://api.together.xyz/v1/models',
          models: [
            ModelConfig(modelId: 'meta-llama/Llama-3.3-70B-Instruct-Turbo', displayName: 'Llama 3.3 70B', maxTokens: 4096),
          ],
        ),
        ProviderConfig(
          name: 'Ollama Cloud',
          baseUrl: 'https://ollama.com/v1',
          modelsEndpoint: 'https://ollama.com/v1/models',
          models: [
            ModelConfig(modelId: 'glm-5.1:cloud', displayName: 'GLM 5.1 Cloud', maxTokens: 4096, contextWindow: 128000, description: 'Zhipu GLM 5.1 via Ollama Cloud'),
            ModelConfig(modelId: 'kimi-k2.6', displayName: 'Kimi K2.6', maxTokens: 4096, contextWindow: 128000, description: 'Moonshot Kimi K2.6'),
            ModelConfig(modelId: 'deepseek-v3.2', displayName: 'DeepSeek V3.2', maxTokens: 4096, contextWindow: 128000, description: 'DeepSeek V3.2 671B'),
            ModelConfig(modelId: 'qwen3.5:397b', displayName: 'Qwen 3.5 397B', maxTokens: 4096, contextWindow: 128000, description: 'Alibaba Qwen 3.5'),
          ],
        ),
        ProviderConfig(
          name: 'Custom / Self-hosted',
          baseUrl: 'http://localhost:8000/v1',
        ),
      ];
}