package com.kolo.agent.core.providers.openai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OpenAiStreamClientTest {
    private val client = OpenAiStreamClient()

    @Test
    fun parseModelListResponse_keepsOllamaModelIdsFromOpenAiCompatibleEndpoint() {
        val body = """
            {
              "object": "list",
              "data": [
                {"id": "glm-5.1", "object": "model", "owned_by": "ollama"},
                {"id": "qwen3.5:397b", "object": "model", "owned_by": "ollama"}
              ]
            }
        """.trimIndent()

        val models = client.parseModelListResponse(body)

        assertEquals(listOf("glm-5.1" to null, "qwen3.5:397b" to null), models)
    }

    @Test
    fun parseModelListResponse_supportsOllamaTagsShape() {
        val body = """
            {
              "models": [
                {"name": "deepseek-v3.2", "model": "deepseek-v3.2"},
                {"name": "kimi-k2-thinking", "model": "kimi-k2-thinking"}
              ]
            }
        """.trimIndent()

        val models = client.parseModelListResponse(body)

        assertEquals(listOf("deepseek-v3.2" to null, "kimi-k2-thinking" to null), models)
    }

    @Test
    fun parseModelListResponse_preservesExplicitDisplayNames() {
        val body = """
            {
              "data": [
                {"id": "gpt-4o", "display_name": "GPT-4o"},
                {"id": "gpt-4o-mini", "displayName": "GPT-4o Mini"}
              ]
            }
        """.trimIndent()

        val models = client.parseModelListResponse(body)

        assertEquals("gpt-4o", models[0].first)
        assertEquals("GPT-4o", models[0].second)
        assertEquals("gpt-4o-mini", models[1].first)
        assertEquals("GPT-4o Mini", models[1].second)
    }

    @Test
    fun parseModelListResponse_doesNotUseOwnerAsDisplayName() {
        val body = """{"data":[{"id":"deepseek-v3.2","owned_by":"ollama"}]}"""

        val models = client.parseModelListResponse(body)

        assertEquals("deepseek-v3.2", models.single().first)
        assertNull(models.single().second)
    }
}
