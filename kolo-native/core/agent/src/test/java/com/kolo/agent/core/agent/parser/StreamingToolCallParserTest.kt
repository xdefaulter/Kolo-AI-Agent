package com.kolo.agent.core.agent.parser

import com.kolo.agent.core.providers.openai.ToolCallDelta
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class StreamingToolCallParserTest {

    private lateinit var parser: StreamingToolCallParser

    @Before
    fun setup() {
        parser = StreamingToolCallParser()
    }

    @Test
    fun `no deltas returns empty list`() {
        val result = parser.resolve()
        assertTrue(result.isEmpty())
    }

    @Test
    fun `single tool call with fragments resolves correctly`() {
        // First delta: id + name
        parser.processDeltas(listOf(
            ToolCallDelta(index = 0, id = "call_123", name = "calculator", argumentsFragment = null)
        ))

        // Second delta: argument fragments
        parser.processDeltas(listOf(
            ToolCallDelta(index = 0, id = null, name = null, argumentsFragment = "{\"expre")
        ))

        parser.processDeltas(listOf(
            ToolCallDelta(index = 0, id = null, name = null, argumentsFragment = "ssion\": \"2+2\"}")
        ))

        val result = parser.resolve()
        assertEquals(1, result.size)
        assertEquals("call_123", result[0].id)
        assertEquals("calculator", result[0].name)
        assertTrue(result[0].arguments.contains("2+2"))
    }

    @Test
    fun `multiple tool calls resolve correctly`() {
        // First tool call
        parser.processDeltas(listOf(
            ToolCallDelta(index = 0, id = "call_1", name = "calculator", argumentsFragment = null)
        ))
        parser.processDeltas(listOf(
            ToolCallDelta(index = 0, id = null, name = null, argumentsFragment = "{\"expression\": \"2+2\"}")
        ))

        // Second tool call
        parser.processDeltas(listOf(
            ToolCallDelta(index = 1, id = "call_2", name = "date", argumentsFragment = null)
        ))
        parser.processDeltas(listOf(
            ToolCallDelta(index = 1, id = null, name = null, argumentsFragment = "{}")
        ))

        val result = parser.resolve()
        assertEquals(2, result.size)
        assertEquals("calculator", result[0].name)
        assertEquals("date", result[1].name)
    }

    @Test
    fun `fresh parser returns empty`() {
        val freshParser = StreamingToolCallParser()
        val result = freshParser.resolve()
        assertTrue(result.isEmpty())
    }
}