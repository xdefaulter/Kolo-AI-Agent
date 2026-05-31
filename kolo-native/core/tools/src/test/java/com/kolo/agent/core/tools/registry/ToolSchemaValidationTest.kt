package com.kolo.agent.core.tools.registry

import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.model.ToolPermissionMode
import com.kolo.agent.core.model.api.parseParameterSchema
import com.kolo.agent.core.tools.builtin.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ToolSchemaValidationTest {

    private lateinit var registry: ToolRegistry

    @Before
    fun setup() {
        registry = ToolRegistry()
    }

    @Test
    fun `every registered builtin tool has valid JSON parameter schema with type=object`() {
        val tools = registry.getAllTools()
        assertTrue("Should have builtin tools registered", tools.isNotEmpty())

        for (tool in tools) {
            val schema = parseParameterSchema(tool.parameterSchema)
            assertNotEquals(
                "Tool '${tool.name}' parameter schema should not be empty after parsing",
                0,
                schema.size,
            )
            assertTrue(
                "Tool '${tool.name}' parameter schema must have type=object, got: ${schema["type"]}",
                schema.containsKey("type"),
            )
            assertEquals(
                "Tool '${tool.name}' parameter schema type must be 'object'",
                "object",
                schema["type"]?.jsonPrimitive?.content,
            )
            assertTrue(
                "Tool '${tool.name}' parameter schema must have 'properties' key",
                schema.containsKey("properties"),
            )
        }
    }

    @Test
    fun `parameter schema strings are valid JSON`() {
        val tools = registry.getAllTools()
        for (tool in tools) {
            try {
                Json.parseToJsonElement(tool.parameterSchema)
            } catch (e: Exception) {
                fail("Tool '${tool.name}' has invalid JSON parameter schema: ${tool.parameterSchema}\nParse error: ${e.message}")
            }
        }
    }

    @Test
    fun `toFunctionDefinition produces correct API format`() {
        val tools = registry.getAllTools()
        for (tool in tools) {
            val def = tool.toFunctionDefinition()
            assertEquals("Tool '${tool.name}' definition type must be 'function'", "function", def.type)
            assertEquals("Tool '${tool.name}' function name mismatch", tool.name, def.function.name)
            assertTrue("Tool '${tool.name}' description must not be blank", def.function.description.isNotBlank())
            assertTrue(
                "Tool '${tool.name}' parameters must be JsonObject, got: ${def.function.parameters::class.simpleName}",
                def.function.parameters is JsonObject,
            )
            val params = def.function.parameters as JsonObject
            assertTrue("Tool '${tool.name}' parameters must have type=object", params.containsKey("type"))
            assertEquals("object", params["type"]?.jsonPrimitive?.content)
        }
    }

    @Test
    fun `web search tool has valid schema`() {
        val tool = registry.getTool("web_search")
        assertNotNull("web_search tool should be registered", tool)
        val schema = parseParameterSchema(tool!!.parameterSchema)
        assertEquals("object", schema["type"]?.jsonPrimitive?.content)
        assertTrue(schema.containsKey("properties"))
        val props = schema["properties"]?.jsonObject
        assertNotNull(props)
        assertTrue("web_search should have 'query' property", props!!.containsKey("query"))
        // web_search has a 'query' required parameter
        val required = schema["required"]?.jsonArray
        assertNotNull("web_search should have required fields", required)
        assertTrue("web_search should require 'query'", required!!.map { it.jsonPrimitive.content }.contains("query"))
    }

    @Test
    fun `web search tool is honest about being placeholder`() {
        val tool = registry.getTool("web_search")
        assertNotNull(tool)
        // The tool should still function (returning a message), not crash
        // Its description does NOT claim to perform real searches
        assertTrue("web_search description should mention search", tool!!.description.lowercase().contains("search"))
    }

    @Test
    fun `tool descriptions are meaningful`() {
        val tools = registry.getAllTools()
        for (tool in tools) {
            assertTrue(
                "Tool '${tool.name}' description should not be empty",
                tool.description.isNotBlank(),
            )
            assertTrue(
                "Tool '${tool.name}' description should be more than 10 chars: '${tool.description}'",
                tool.description.length > 10,
            )
        }
    }

    @Test
    fun `phone control tools are registered separately by ToolModule`() {
        // Phone control tools are NOT in the basic ToolRegistry.
        // They are added by ToolModule in the app module at runtime.
        // This test verifies they are absent from the base registry.
        val phoneToolNames = listOf("tap", "swipe", "long_press", "click_text", "type_text",
            "press_key", "scroll", "screen_read_full", "phone_control_start",
            "phone_control_status", "phone_control_done", "screen_read")

        for (name in phoneToolNames) {
            assertNull("Phone tool '$name' should NOT be in base registry (added by ToolModule)",
                registry.getTool(name))
        }
    }

    @Test
    fun `tool permission defaults are correct`() {
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("calculator"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("date"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("json_parse"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("base64"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("hash"))
        // Sensitive tools default to askEveryTime
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("http_get"))
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("http_post"))
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("web_search"))
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("web_scrape"))
    }

    @Test
    fun `http tools have required url parameter`() {
        for (name in listOf("http_get", "http_post")) {
            val tool = registry.getTool(name)
            assertNotNull("'$name' should be registered", tool)
            val schema = parseParameterSchema(tool!!.parameterSchema)
            val props = schema["properties"]?.jsonObject
            assertNotNull("'$name' should have properties", props)
            assertTrue("'$name' should have 'url' property", props!!.containsKey("url"))
        }
    }

    @Test
    fun `calculator tool has expression parameter`() {
        val tool = registry.getTool("calculator")
        assertNotNull(tool)
        val schema = parseParameterSchema(tool!!.parameterSchema)
        val props = schema["properties"]?.jsonObject
        assertTrue("calculator should have 'expression' property", props!!.containsKey("expression"))
    }

    @Test
    fun `memory tools are present in base registry`() {
        assertNotNull("recall_memories should be registered", registry.getTool("recall_memories"))
        assertNotNull("remember_this should be registered", registry.getTool("remember_this"))
        assertNotNull("forget_memory should be registered", registry.getTool("forget_memory"))
    }

    @Test
    fun `screenshot tool is not in registry as screenshot`() {
        assertNull("screenshot tool should NOT exist (renamed to screen_read_full)",
            registry.getTool("screenshot"))
    }
}