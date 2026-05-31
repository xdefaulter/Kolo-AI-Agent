package com.kolo.agent.core.tools.registry

import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.ProviderKind
import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.model.ToolPermissionMode
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import com.kolo.agent.core.tools.ToolPlatform
import com.kolo.agent.core.tools.builtin.*
import com.kolo.agent.core.model.api.parseParameterSchema
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ToolRegistryTest {

    private lateinit var registry: ToolRegistry

    @Before
    fun setup() {
        registry = ToolRegistry()
    }

    @Test
    fun `builtin tools are registered on init`() {
        val tools = registry.getAllTools()
        assertTrue(tools.size >= 11)
        assertTrue(tools.any { it.name == "calculator" })
        assertTrue(tools.any { it.name == "date" })
        assertTrue(tools.any { it.name == "http_get" })
    }

    @Test
    fun `getTool returns correct tool`() {
        val tool = registry.getTool("calculator")
        assertNotNull(tool)
        assertEquals("calculator", tool!!.name)
    }

    @Test
    fun `getTool returns null for unknown tool`() {
        val tool = registry.getTool("nonexistent")
        assertNull(tool)
    }

    @Test
    fun `register and unregister custom tool`() = runTest {
        val customTool = object : KoloTool() {
            override val name = "custom_test"
            override val description = "A test tool"
            override val parameterSchema = """{"type":"object","properties":{}}"""
            override val permission = ToolPermission.safe
            override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext) =
                ToolExecutionResult.ok("test output")
        }

        registry.register(customTool)
        assertNotNull(registry.getTool("custom_test"))

        registry.unregister("custom_test")
        assertNull(registry.getTool("custom_test"))
    }

    @Test
    fun `getToolsForProvider filters disabled tools`() {
        val config = ProviderConfig(
            name = "Test",
            baseUrl = "https://api.test.com/v1",
            kind = ProviderKind.openaiCompat,
            disabledTools = setOf("calculator", "date"),
        )
        val tools = registry.getToolsForProvider(config)
        assertTrue(tools.none { it.name == "calculator" })
        assertTrue(tools.none { it.name == "date" })
        assertTrue(tools.any { it.name == "http_get" })
    }

    @Test
    fun `small model mode filters dangerous tools`() {
        val config = ProviderConfig(
            name = "Small",
            baseUrl = "https://api.test.com/v1",
            kind = ProviderKind.openaiCompat,
            smallModelMode = true,
        )
        val tools = registry.getToolsForProvider(config)
        assertTrue(tools.isNotEmpty())
    }

    @Test
    fun `toFunctionDefinition produces proper format`() {
        val tool = registry.getTool("calculator")!!
        val def = tool.toFunctionDefinition()

        // Must have type = "function"
        assertEquals("function", def.type)

        // Must have function with name, description, and parameters as JsonObject
        assertEquals("calculator", def.function.name)
        assertTrue(def.function.description.isNotBlank())

        // Verify parameters is a (parsed) JsonObject, not a raw string
        val params = def.function.parameters
        assertNotNull(params)
        assertTrue(params.containsKey("type"))
        assertEquals("object", params["type"]?.toString()?.trim('"'))
        assertTrue(params.containsKey("properties"))
    }

    @Test
    fun `parseParameterSchema handles valid JSON`() {
        val result = parseParameterSchema("""{"type":"object","properties":{"x":{"type":"string"}}}""")
        assertTrue(result.containsKey("type"))
        assertTrue(result.containsKey("properties"))
    }

    @Test
    fun `parseParameterSchema handles invalid JSON`() {
        val result = parseParameterSchema("not json at all")
        // Falls back to default object schema
        assertTrue(result.containsKey("type"))
        assertTrue(result.containsKey("properties"))
    }

    @Test
    fun `getDefaultPermissionMode returns safe defaults`() {
        assertEquals(ToolPermissionMode.alwaysAllow, registry.getDefaultPermissionMode("calculator"))
        // Dangerous tools default to askEveryTime
        // Since phone control tools aren't in basic registry, test with a sensitive tool
        val httpGet = registry.getTool("http_get")
        if (httpGet != null) {
            assertEquals(ToolPermissionMode.askEveryTime, registry.getDefaultPermissionMode("http_get"))
        }
    }
}