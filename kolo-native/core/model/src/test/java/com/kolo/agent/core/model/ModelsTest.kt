package com.kolo.agent.core.model

import org.junit.Assert.*
import org.junit.Test

class ModelsTest {

    @Test
    fun providerConfigEffectiveModelsUrlReturnsModelsEndpoint() {
        val config = ProviderConfig(
            name = "Test",
            baseUrl = "https://api.openai.com/v1",
            modelsEndpoint = "https://api.openai.com/v1/models",
        )
        assertEquals("https://api.openai.com/v1/models", config.effectiveModelsUrl)
    }

    @Test
    fun providerConfigEffectiveModelsUrlFallsBackToBaseUrl() {
        val config = ProviderConfig(
            name = "Test",
            baseUrl = "https://api.openai.com/v1",
        )
        assertEquals("https://api.openai.com/v1/models", config.effectiveModelsUrl)
    }

    @Test
    fun providerConfigActiveModelReturnsFirstActiveModel() {
        val config = ProviderConfig(
            name = "Test",
            baseUrl = "https://api.test.com/v1",
            models = listOf(
                ModelConfig(modelId = "model-a", isActive = false),
                ModelConfig(modelId = "model-b", isActive = true),
                ModelConfig(modelId = "model-c", isActive = false),
            ),
        )
        assertEquals("model-b", config.activeModel!!.modelId)
    }

    @Test
    fun providerConfigActiveModelFallsBackToFirstModel() {
        val config = ProviderConfig(
            name = "Test",
            baseUrl = "https://api.test.com/v1",
            models = listOf(
                ModelConfig(modelId = "model-a"),
            ),
        )
        assertEquals("model-a", config.activeModel!!.modelId)
    }

    @Test
    fun messageRoleFromWireWorks() {
        assertEquals(MessageRole.user, MessageRole.fromWire("user"))
        assertEquals(MessageRole.assistant, MessageRole.fromWire("assistant"))
        assertEquals(MessageRole.system, MessageRole.fromWire("system"))
        assertEquals(MessageRole.tool, MessageRole.fromWire("tool"))
        assertEquals(MessageRole.user, MessageRole.fromWire("unknown"))
    }

    @Test
    fun messageRoleWirePropertyWorks() {
        assertEquals("user", MessageRole.user.wire)
        assertEquals("assistant", MessageRole.assistant.wire)
        assertEquals("system", MessageRole.system.wire)
        assertEquals("tool", MessageRole.tool.wire)
    }

    @Test
    fun providerKindFromWireWorks() {
        assertEquals(ProviderKind.openaiCompat, ProviderKind.fromWire("openai"))
        assertEquals(ProviderKind.localLlama, ProviderKind.fromWire("local-llama"))
        assertEquals(ProviderKind.openaiCompat, ProviderKind.fromWire(null))
    }

    @Test
    fun providerKindWirePropertyWorks() {
        assertEquals("openai", ProviderKind.openaiCompat.wire)
        assertEquals("local-llama", ProviderKind.localLlama.wire)
    }

    @Test
    fun toolExecutionResultOkCreatesSuccessResult() {
        val result = ToolExecutionResult.ok("output text")
        assertTrue(result.success)
        assertEquals("output text", result.output)
        assertNull(result.error)
    }

    @Test
    fun toolExecutionResultErrCreatesErrorResult() {
        val result = ToolExecutionResult.err("something failed")
        assertFalse(result.success)
        assertEquals("", result.output)
        assertEquals("something failed", result.error)
    }

    @Test
    fun providerPresetsContainsExpectedDefaults() {
        assertTrue(ProviderPresets.defaults.isNotEmpty())
        assertTrue(ProviderPresets.defaults.any { it.name == "OpenAI" })
        assertTrue(ProviderPresets.defaults.any { it.name == "Groq" })
        assertTrue(ProviderPresets.defaults.any { it.name == "Ollama (Local)" })
        assertTrue(ProviderPresets.defaults.any { provider ->
            provider.name == "Ollama Cloud" &&
                provider.models.any { it.modelId == "glm-5.1" } &&
                provider.models.none { it.modelId.endsWith(":cloud") }
        })
    }

    @Test
    fun modelConfigLabelReturnsDisplayNameOrModelId() {
        val withDisplay = ModelConfig(modelId = "gpt-4o", displayName = "GPT-4o")
        assertEquals("GPT-4o", withDisplay.label)

        val withoutDisplay = ModelConfig(modelId = "gpt-4o")
        assertEquals("gpt-4o", withoutDisplay.label)
    }
}
