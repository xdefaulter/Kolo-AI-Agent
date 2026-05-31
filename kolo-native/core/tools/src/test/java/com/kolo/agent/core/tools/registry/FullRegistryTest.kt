package com.kolo.agent.core.tools.registry

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.model.ToolPermissionMode
import com.kolo.agent.core.model.api.parseParameterSchema
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import com.kolo.agent.core.tools.builtin.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Tests for the full tool registry including phone-control tools.
 * Phone-control tools are included by creating them without the AccessibilityService
 * (they will return "service not running" errors at execution time, which is correct).
 */
class FullRegistryTest {

    private lateinit var registry: ToolRegistry

    @Before
    fun setup() {
        registry = ToolRegistry()
        // Register phone-control tools (same as ToolModule does)
        registerPhoneControlTools()
    }

    private fun registerPhoneControlTools() {
        // These are the same tools that ToolModule registers in the real app
        // We can't import from feature:phonecontrol in unit tests (Android dependency),
        // so we create minimal stubs to verify schema correctness
        registry.register(StubPhoneTool("tap", "Tap at specific coordinates", """{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"}},"required":["x","y"]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("swipe", "Perform a swipe gesture", """{"type":"object","properties":{"start_x":{"type":"integer"},"start_y":{"type":"integer"},"end_x":{"type":"integer"},"end_y":{"type":"integer"},"duration":{"type":"integer"}},"required":["start_x","start_y","end_x","end_y"]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("long_press", "Perform a long press", """{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"},"duration":{"type":"integer"}},"required":["x","y"]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("click_text", "Find and click UI element by text", """{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("type_text", "Type text into focused input field", """{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("press_key", "Press a system key. Supported keys: back, home, recents, notifications, quick_settings, power_dialog, enter, tab, delete.", """{"type":"object","properties":{"key":{"type":"string","description":"Key to press: back, home, recents, notifications, quick_settings, power_dialog, enter, tab, delete"}},"required":["key"]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("scroll", "Scroll in a direction", """{"type":"object","properties":{"direction":{"type":"string"},"distance":{"type":"integer"}},"required":["direction"]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("screen_read_full", "Read the full accessibility tree", """{"type":"object","properties":{},"required":[]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("phone_control_start", "Start phone control session", """{"type":"object","properties":{"reason":{"type":"string"}},"required":[]}""", ToolPermission.dangerous))
        registry.register(StubPhoneTool("phone_control_status", "Check phone control status", """{"type":"object","properties":{},"required":[]}""", ToolPermission.safe))
        registry.register(StubPhoneTool("phone_control_done", "End phone control session", """{"type":"object","properties":{"message":{"type":"string"}},"required":[]}""", ToolPermission.safe))
        registry.register(StubPhoneTool("screen_read", "Read the accessibility tree", """{"type":"object","properties":{},"required":[]}""", ToolPermission.dangerous))
    }

    @Test
    fun `full registry has builtin plus phone-control tools`() {
        val tools = registry.getAllTools()
        // Builtins: calculator, date, json_parse, base64, hash, http_get, http_post, web_search, web_scrape, recall_memories, remember_this, forget_memory
        // Phone: tap, swipe, long_press, click_text, type_text, press_key, scroll, screen_read_full, phone_control_start, phone_control_status, phone_control_done, screen_read
        assertTrue("Registry should have at least 24 tools, got ${tools.size}", tools.size >= 24)

        // Verify each expected tool exists
        val expectedTools = listOf(
            "calculator", "date", "json_parse", "base64", "hash",
            "http_get", "http_post", "web_search", "web_scrape",
            "recall_memories", "remember_this", "forget_memory",
            "tap", "swipe", "long_press", "click_text", "type_text",
            "press_key", "scroll", "screen_read_full",
            "phone_control_start", "phone_control_status", "phone_control_done",
            "screen_read",
        )
        for (name in expectedTools) {
            assertNotNull("Tool '$name' should be registered", registry.getTool(name))
        }
    }

    @Test
    fun `every registered tool has valid JSON parameter schema with type=object`() {
        val tools = registry.getAllTools()
        assertTrue("Should have tools registered", tools.isNotEmpty())

        for (tool in tools) {
            val schema = parseParameterSchema(tool.parameterSchema)
            assertNotEquals(
                "Tool '${tool.name}' parameter schema should not be empty after parsing",
                0,
                schema.size,
            )
            assertTrue(
                "Tool '${tool.name}' parameter schema must have 'type' key",
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
    }

    @Test
    fun `press_key tool has correct supported keys in description`() {
        val tool = registry.getTool("press_key")
        assertNotNull("press_key tool should be registered", tool)
        val supportedKeys = listOf("back", "home", "recents", "notifications", "quick_settings", "power_dialog", "enter", "tab", "delete")
        for (key in supportedKeys) {
            assertTrue(
                "press_key description should mention key '$key'",
                tool!!.description.lowercase().contains(key),
            )
        }
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
    fun `phone control tools are dangerous except status and done`() {
        val safePhoneTools = listOf("phone_control_status", "phone_control_done", "show_action")
        val dangerousPhoneTools = listOf(
            "tap", "swipe", "long_press", "click_text", "type_text",
            "press_key", "scroll", "screen_read_full", "screen_read", "phone_control_start",
        )

        for (name in dangerousPhoneTools) {
            val tool = registry.getTool(name)
            if (tool != null) {
                assertEquals("Dangerous phone tool '$name' should have dangerous permission",
                    ToolPermission.dangerous, tool.permission)
            }
        }
        for (name in safePhoneTools) {
            val tool = registry.getTool(name)
            // show_action and phone_control_done may not be in the stub registry
            if (tool != null) {
                assertTrue("Safe phone tool '$name' should have safe permission",
                    tool.permission == ToolPermission.safe || tool.permission == ToolPermission.sensitive)
            }
        }
    }

    @Test
    fun `tool permission defaults are correct`() {
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("calculator"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("date"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("json_parse"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("base64"))
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("hash"))
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("http_get"))
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("web_search"))
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("tap"))
        assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("press_key"))
    }

    @Test
    fun `screenshot is not advertised as visual capture`() {
        val screenRead = registry.getTool("screen_read_full")
        assertNotNull("screen_read_full should be registered", screenRead)
        // Must explicitly say it returns accessibility tree, NOT a screenshot
        assertTrue(
            "screen_read_full description must not claim to be a screenshot",
            !screenRead!!.description.lowercase().contains("screenshot"),
        )
        assertTrue(
            "screen_read_full description must mention accessibility tree",
            screenRead.description.lowercase().contains("accessibility tree") ||
                screenRead.description.lowercase().contains("accessibility"),
        )
    }
}

/** Stub tool for phone-control tools in unit tests (no Android dependency). */
private class StubPhoneTool(
    override val name: String,
    override val description: String,
    override val parameterSchema: String,
    override val permission: ToolPermission,
) : KoloTool() {
    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        return ToolExecutionResult.err("Phone control not available in test environment")
    }
}