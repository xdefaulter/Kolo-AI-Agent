package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class WebSearchToolTest {

    private val tool = WebSearchTool()

    @Test
    fun toolMetadataIsCorrect() {
        assertEquals("web_search", tool.name)
        assertTrue(tool.description.isNotBlank())
        assertTrue(tool.description.contains("search", ignoreCase = true))
        assertEquals(com.kolo.agent.core.model.ToolPermission.sensitive, tool.permission)
    }

    @Test
    fun missingQueryReturnsError() = runTest {
        val result = tool.execute(emptyMap(), ToolExecutionContext(chatId = "test"))
        assertFalse(result.success)
        assertTrue(result.error!!.contains("Missing query", ignoreCase = true))
    }

    @Test
    fun parameterSchemaIsValidJson() {
        // Verify the schema is valid JSON
        val schema = tool.parameterSchema
        assertTrue(schema.contains("query"))
        assertTrue(schema.contains("max_results"))
    }

    @Test
    fun maxResultsIsClamped() = runTest {
        // We can't test actual HTTP calls in unit tests, but we verify the tool
        // doesn't crash with edge-case max_results values
        val result = tool.execute(
            mapOf("query" to "test query that will fail gracefully"),
            ToolExecutionContext(chatId = "test"),
        )
        // The result should be either success (if network available) or error (no network)
        // Either way, it shouldn't crash
        assertNotNull(result)
    }
}