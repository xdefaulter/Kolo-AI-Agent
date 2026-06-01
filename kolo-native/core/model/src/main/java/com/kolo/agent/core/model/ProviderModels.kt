package com.kolo.agent.core.model

import kotlinx.serialization.Serializable

@Serializable
enum class ProviderKind {
    openaiCompat,
    localLlama;

    val wire: String get() = when (this) {
        openaiCompat -> "openai"
        localLlama -> "local-llama"
    }

    companion object {
        fun fromWire(s: String?): ProviderKind = when (s) {
            "local-llama" -> localLlama
            else -> openaiCompat
        }
    }
}

/**
 * An API provider configuration.
 * API keys are stored separately in SecureKeyStore — not in this data class.
 */
@Serializable
data class ProviderConfig(
    val id: ProviderId = ProviderId(java.util.UUID.randomUUID().toString()),
    val name: String,
    val baseUrl: String,
    val customHeaders: Map<String, String> = emptyMap(),
    val isActive: Boolean = false,
    val modelsEndpoint: String? = null,
    val kind: ProviderKind = ProviderKind.openaiCompat,
    val modelPath: String? = null,
    val localGpuLayers: Int = 0,
    val disabledTools: Set<String> = emptySet(),
    val smallModelMode: Boolean = false,
    val models: List<ModelConfig> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val effectiveModelsUrl: String
        get() {
            if (!modelsEndpoint.isNullOrBlank()) return modelsEndpoint
            val base = baseUrl.trimEnd('/')
            return "$base/models"
        }

    val activeModel: ModelConfig?
        get() = models.firstOrNull { it.isActive } ?: models.firstOrNull()

    val isLocal: Boolean
        get() = kind == ProviderKind.localLlama

    val canFetchModels: Boolean
        get() = !modelsEndpoint.isNullOrBlank()
}

/**
 * A model within a provider.
 */
@Serializable
data class ModelConfig(
    val id: String = java.util.UUID.randomUUID().toString(),
    val modelId: String,
    val displayName: String? = null,
    val maxTokens: Int = 4096,
    val temperature: Double = 0.7,
    val contextWindow: Int? = null,
    val isActive: Boolean = false,
    val isCustom: Boolean = false,
    val description: String? = null,
) {
    val label: String get() = displayName ?: modelId
}

/**
 * A custom tool definition authored by the user.
 */
@Serializable
data class CustomToolDef(
    val id: CustomToolId = CustomToolId(java.util.UUID.randomUUID().toString()),
    val name: String,
    val description: String,
    val kind: CustomToolKind = CustomToolKind.prompt,
    val parameterSchema: String = "{}",
    val systemPrompt: String = "",
    val userMessage: String = "",
    val steps: List<ComposedStep> = emptyList(),
    val permission: ToolPermission = ToolPermission.sensitive,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)

@Serializable
enum class CustomToolKind {
    prompt, composed
}

@Serializable
data class ComposedStep(
    val toolName: String,
    val params: Map<String, String> = emptyMap(),
)

/**
 * A skill — a persisted multi-step playbook injected into the system prompt.
 */
@Serializable
data class Skill(
    val id: SkillId = SkillId(java.util.UUID.randomUUID().toString()),
    val name: String,
    val description: String,
    val content: String,
    val isEnabled: Boolean = true,
    val isAgentAuthored: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)

/**
 * Tool permission levels.
 */
@Serializable
enum class ToolPermission {
    safe, sensitive, dangerous
}

/**
 * Per-tool permission modes.
 */
@Serializable
enum class ToolPermissionMode {
    alwaysAllow, askEveryTime, neverAllow
}

/**
 * Well-known provider presets for quick setup.
 */
object ProviderPresets {
    val defaults: List<ProviderConfig> get() = listOf(
        ProviderConfig(
            name = "OpenAI",
            baseUrl = "https://api.openai.com/v1",
            modelsEndpoint = "https://api.openai.com/v1/models",
            models = listOf(
                ModelConfig(modelId = "gpt-4o", displayName = "GPT-4o", maxTokens = 4096, contextWindow = 128000, description = "Most capable GPT-4 model"),
                ModelConfig(modelId = "gpt-4o-mini", displayName = "GPT-4o Mini", maxTokens = 4096, contextWindow = 128000, description = "Fast and affordable"),
                ModelConfig(modelId = "o1", displayName = "o1", maxTokens = 4096, contextWindow = 200000, description = "Reasoning model"),
                ModelConfig(modelId = "o1-mini", displayName = "o1 Mini", maxTokens = 4096, contextWindow = 128000, description = "Fast reasoning"),
            ),
        ),
        ProviderConfig(
            name = "Groq",
            baseUrl = "https://api.groq.com/openai/v1",
            modelsEndpoint = "https://api.groq.com/openai/v1/models",
            models = listOf(
                ModelConfig(modelId = "llama-3.3-70b-versatile", displayName = "Llama 3.3 70B", maxTokens = 4096),
            ),
        ),
        ProviderConfig(
            name = "OpenRouter",
            baseUrl = "https://openrouter.ai/api/v1",
            modelsEndpoint = "https://openrouter.ai/api/v1/models",
            models = listOf(
                ModelConfig(modelId = "anthropic/claude-sonnet-4-20250514", displayName = "Claude Sonnet 4", maxTokens = 4096, contextWindow = 200000),
                ModelConfig(modelId = "google/gemini-2.5-pro", displayName = "Gemini 2.5 Pro", maxTokens = 4096, contextWindow = 1000000),
            ),
        ),
        ProviderConfig(
            name = "Ollama (Local)",
            baseUrl = "http://localhost:11434/v1",
            modelsEndpoint = "http://localhost:11434/v1/models",
            models = listOf(
                ModelConfig(modelId = "llama3.2", displayName = "Llama 3.2", maxTokens = 4096, contextWindow = 128000),
            ),
        ),
        ProviderConfig(
            name = "Fireworks AI",
            baseUrl = "https://api.fireworks.ai/inference/v1",
            modelsEndpoint = "https://api.fireworks.ai/v1/accounts/fireworks/models?filter=supports_serverless%3Dtrue&pageSize=100",
            models = listOf(
                ModelConfig(modelId = "accounts/fireworks/models/llama-v3p3-70b-instruct", displayName = "Llama 3.3 70B", maxTokens = 4096),
            ),
        ),
        ProviderConfig(
            name = "Together AI",
            baseUrl = "https://api.together.xyz/v1",
            modelsEndpoint = "https://api.together.xyz/v1/models",
            models = listOf(
                ModelConfig(modelId = "meta-llama/Llama-3.3-70B-Instruct-Turbo", displayName = "Llama 3.3 70B", maxTokens = 4096),
            ),
        ),
        ProviderConfig(
            name = "Ollama Cloud",
            baseUrl = "https://ollama.com/v1",
            modelsEndpoint = "https://ollama.com/v1/models",
            models = listOf(
                ModelConfig(modelId = "glm-5.1:cloud", displayName = "GLM 5.1 Cloud", maxTokens = 4096, contextWindow = 128000, description = "Zhipu GLM 5.1 via Ollama Cloud"),
                ModelConfig(modelId = "kimi-k2.6", displayName = "Kimi K2.6", maxTokens = 4096, contextWindow = 128000, description = "Moonshot Kimi K2.6"),
                ModelConfig(modelId = "deepseek-v3.2", displayName = "DeepSeek V3.2", maxTokens = 4096, contextWindow = 128000, description = "DeepSeek V3.2"),
                ModelConfig(modelId = "qwen3.5:397b", displayName = "Qwen 3.5 397B", maxTokens = 4096, contextWindow = 128000, description = "Alibaba Qwen 3.5"),
            ),
        ),
        ProviderConfig(
            name = "Custom / Self-hosted",
            baseUrl = "http://localhost:8000/v1",
        ),
    )
}
