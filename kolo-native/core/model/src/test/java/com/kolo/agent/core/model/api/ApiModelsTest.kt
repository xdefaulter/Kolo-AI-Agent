package com.kolo.agent.core.model.api

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class ApiModelsTest {

    // ───── ApiMessage serialization tests ─────

    @Test
    fun systemMessageSerializesCorrectly() {
        val msg = ApiMessage(role = "system", content = "You are a helpful assistant.")
        val jsonObj = msg.toJson()

        assertEquals("system", jsonObj["role"]?.jsonPrimitive?.content)
        assertEquals("You are a helpful assistant.", jsonObj["content"]?.jsonPrimitive?.content)
        assertNull(jsonObj["tool_calls"])
        assertNull(jsonObj["tool_call_id"])
    }

    @Test
    fun userMessageSerializesCorrectly() {
        val msg = ApiMessage(role = "user", content = "Hello!")
        val jsonObj = msg.toJson()

        assertEquals("user", jsonObj["role"]?.jsonPrimitive?.content)
        assertEquals("Hello!", jsonObj["content"]?.jsonPrimitive?.content)
    }

    @Test
    fun assistantMessageWithToolCallsSerializesCorrectly() {
        val msg = ApiMessage(
            role = "assistant",
            content = null,
            toolCalls = listOf(
                ApiToolCall(
                    id = "call_abc123",
                    type = "function",
                    function = ApiFunctionCall(
                        name = "calculator",
                        arguments = """{"expression":"2+2"}""",
                    )
                )
            )
        )
        val jsonObj = msg.toJson()

        assertEquals("assistant", jsonObj["role"]?.jsonPrimitive?.content)
        assertNotNull(jsonObj["tool_calls"])
        val toolCallsArray = jsonObj["tool_calls"]!!.jsonArray
        assertEquals(1, toolCallsArray.size)

        val tc = toolCallsArray[0].jsonObject
        assertEquals("call_abc123", tc["id"]?.jsonPrimitive?.content)
        assertEquals("function", tc["type"]?.jsonPrimitive?.content)

        val fn = tc["function"]?.jsonObject
        assertNotNull(fn)
        assertEquals("calculator", fn!!["name"]?.jsonPrimitive?.content)
        assertEquals("""{"expression":"2+2"}""", fn["arguments"]?.jsonPrimitive?.content)
    }

    @Test
    fun toolResultMessageSerializesCorrectly() {
        val msg = ApiMessage(
            role = "tool",
            content = "4",
            toolCallId = "call_abc123",
        )
        val jsonObj = msg.toJson()

        assertEquals("tool", jsonObj["role"]?.jsonPrimitive?.content)
        assertEquals("4", jsonObj["content"]?.jsonPrimitive?.content)
        assertEquals("call_abc123", jsonObj["tool_call_id"]?.jsonPrimitive?.content)
    }

    // ───── ApiToolDefinition tests ─────

    @Test
    fun toolDefinitionSerializesToJson() {
        val schema = """{"type":"object","properties":{"expression":{"type":"string","description":"Math expression to evaluate"}},"required":["expression"]}"""
        val toolDef = ApiToolDefinition(
            type = "function",
            function = ApiFunctionDef(
                name = "calculator",
                description = "Evaluate mathematical expressions",
                parameters = parseParameterSchema(schema),
            )
        )

        val jsonObj = toolDef.toJson()

        assertEquals("function", jsonObj["type"]?.jsonPrimitive?.content)

        val fn = jsonObj["function"]?.jsonObject
        assertNotNull(fn)
        assertEquals("calculator", fn!!["name"]?.jsonPrimitive?.content)
        assertEquals("Evaluate mathematical expressions", fn["description"]?.jsonPrimitive?.content)

        // Parameters must be a JsonObject, not a string
        val params = fn["parameters"]?.jsonObject
        assertNotNull(params)
        assertEquals("object", params!!["type"]?.jsonPrimitive?.content)
        assertNotNull(params["properties"])
        assertNotNull(params["required"])
    }

    @Test
    fun parseParameterSchemaParsesValidJson() {
        val schema = """{"type":"object","properties":{"x":{"type":"integer"}}}"""
        val result = parseParameterSchema(schema)
        assertEquals("object", result["type"]?.jsonPrimitive?.content)
        assertNotNull(result["properties"])
    }

    @Test
    fun parseParameterSchemaHandlesInvalidJson() {
        val result = parseParameterSchema("not valid json")
        assertEquals("object", result["type"]?.jsonPrimitive?.content)
        assertNotNull(result["properties"])
    }

    @Test
    fun fullRequestStructureIsValid() {
        val messages = listOf(
            ApiMessage(role = "system", content = "You are helpful."),
            ApiMessage(role = "user", content = "What is 2+2?"),
        )
        val tools = listOf(
            ApiToolDefinition(
                function = ApiFunctionDef(
                    name = "calculator",
                    description = "Calculate math",
                    parameters = parseParameterSchema("""{"type":"object","properties":{"expression":{"type":"string"}},"required":["expression"]}"""),
                )
            )
        )

        // Verify messages serialize properly
        val systemJson = messages[0].toJson()
        assertEquals("system", systemJson["role"]?.jsonPrimitive?.content)
        assertEquals("You are helpful.", systemJson["content"]?.jsonPrimitive?.content)

        val userJson = messages[1].toJson()
        assertEquals("user", userJson["role"]?.jsonPrimitive?.content)
        assertEquals("What is 2+2?", userJson["content"]?.jsonPrimitive?.content)

        // Verify tool serializes with proper nested structure
        val toolJson = tools[0].toJson()
        assertEquals("function", toolJson["type"]?.jsonPrimitive?.content)
        val fnObj = toolJson["function"]?.jsonObject
        assertNotNull(fnObj)
        assertEquals("calculator", fnObj!!["name"]?.jsonPrimitive?.content)
        assertEquals("Calculate math", fnObj["description"]?.jsonPrimitive?.content)

        // Parameters must be a JSON object, not a string
        val params = fnObj["parameters"]?.jsonObject
        assertNotNull(params)
        assertEquals("object", params!!["type"]?.jsonPrimitive?.content)
    }
}