package com.kolo.agent.core.agent

import com.kolo.agent.core.model.ResolvedToolCall
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the local-mode tool-call parser recovered from the compiled bytecode.
 *
 * This parser extracts tool calls from raw LLM text output using two regex
 * block patterns (tag-form `<tool_call>...</tool_call>` and fenced
 * ` ```tool_call...``` `), with a fallback to a bare JSON object.
 */
class LocalToolCallParserTest {

    @Test
    fun `tag block with name and arguments is parsed`() {
        val content = """Some preamble.
            |<tool_call>{"name":"calculator","arguments":{"expression":"2+2"}}</tool_call>
        """.trimMargin()

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(1, calls.size)
        assertEquals("calculator", calls[0].name)
        assertEquals("""{"expression":"2+2"}""", calls[0].arguments)
        // id should be a non-empty string
        assertTrue("id must be non-empty", calls[0].id.isNotEmpty())
    }

    @Test
    fun `fenced code block with tool_call marker is parsed`() {
        val content = """
            ```tool_call
            {"name":"date","arguments":{}}
            ```
        """.trimIndent()

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(1, calls.size)
        assertEquals("date", calls[0].name)
        assertEquals("{}", calls[0].arguments)
    }

    @Test
    fun `bare JSON object fallback is parsed when no blocks present`() {
        val content = """{"name":"hash","arguments":{"input":"abc","algorithm":"sha256"}}"""

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(1, calls.size)
        assertEquals("hash", calls[0].name)
        assertEquals("""{"input":"abc","algorithm":"sha256"}""", calls[0].arguments)
    }

    @Test
    fun `tool_name key is accepted as an alias for name`() {
        val content = """<tool_call>{"tool_name":"date","arguments":{}}</tool_call>"""

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(1, calls.size)
        assertEquals("date", calls[0].name)
    }

    @Test
    fun `params key is accepted as an alias for arguments`() {
        val content = """<tool_call>{"name":"date","params":{"format":"iso"}}</tool_call>"""

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(1, calls.size)
        assertEquals("date", calls[0].name)
        assertEquals("""{"format":"iso"}""", calls[0].arguments)
    }

    @Test
    fun `missing arguments defaults to empty JSON object`() {
        val content = """<tool_call>{"name":"date"}</tool_call>"""

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(1, calls.size)
        assertEquals("date", calls[0].name)
        assertEquals("{}", calls[0].arguments)
    }

    @Test
    fun `multiple tag blocks produce multiple calls`() {
        val content = """
            <tool_call>{"name":"date","arguments":{}}</tool_call>
            some text
            <tool_call>{"name":"calculator","arguments":{"expression":"1+1"}}</tool_call>
        """.trimIndent()

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(2, calls.size)
        assertEquals("date", calls[0].name)
        assertEquals("calculator", calls[1].name)
    }

    @Test
    fun `multiple fenced blocks produce multiple calls`() {
        val content = """
            ```tool_call
            {"name":"date","arguments":{}}
            ```
            ```tool_call
            {"name":"calculator","arguments":{"expression":"3*4"}}
            ```
        """.trimIndent()

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(2, calls.size)
        assertEquals("date", calls[0].name)
        assertEquals("calculator", calls[1].name)
    }

    @Test
    fun `each call gets a unique id`() {
        val content = """
            <tool_call>{"name":"date","arguments":{}}</tool_call>
            <tool_call>{"name":"date","arguments":{}}</tool_call>
            <tool_call>{"name":"date","arguments":{}}</tool_call>
        """.trimIndent()

        val calls = LocalToolCallParser.resolve(content)
        val ids = calls.map { it.id }.toSet()

        assertEquals(3, calls.size)
        assertEquals(3, ids.size)
    }

    @Test
    fun `malformed JSON payload is skipped without throwing`() {
        val content = """<tool_call>{not valid json}</tool_call>"""

        val calls = LocalToolCallParser.resolve(content)

        assertTrue("malformed payload should yield no calls, not throw", calls.isEmpty())
    }

    @Test
    fun `payload missing name field is skipped`() {
        val content = """<tool_call>{"arguments":{}}</tool_call>"""

        val calls = LocalToolCallParser.resolve(content)

        assertTrue(calls.isEmpty())
    }

    @Test
    fun `plain text with no tool calls returns empty list`() {
        val content = "Hello! I'm a helpful assistant. The answer is 42."

        val calls = LocalToolCallParser.resolve(content)

        assertTrue(calls.isEmpty())
    }

    @Test
    fun `empty content returns empty list`() {
        val calls = LocalToolCallParser.resolve("")
        assertTrue(calls.isEmpty())
    }

    @Test
    fun `stripToolCalls removes tag blocks`() {
        val content = """
            Here is my plan.
            <tool_call>{"name":"date","arguments":{}}</tool_call>
            Done.
        """.trimIndent()

        val stripped = LocalToolCallParser.stripToolCalls(content)

        assertTrue("tag block removed", !stripped.contains("<tool_call>"))
        assertTrue("preamble kept", stripped.contains("Here is my plan."))
        assertTrue("trailing text kept", stripped.contains("Done."))
    }

    @Test
    fun `stripToolCalls removes fenced blocks`() {
        val content = """
            ```tool_call
            {"name":"date","arguments":{}}
            ```
            After.
        """.trimIndent()

        val stripped = LocalToolCallParser.stripToolCalls(content)

        assertTrue("fence removed", !stripped.contains("tool_call"))
        assertTrue("trailing text kept", stripped.contains("After."))
    }

    @Test
    fun `stripToolCalls leaves plain text untouched`() {
        val content = "Just a normal message with no tool calls."

        val stripped = LocalToolCallParser.stripToolCalls(content)

        assertEquals(content, stripped)
    }

    @Test
    fun `tag block with extra attributes is still parsed`() {
        // The regex uses [^>]* to tolerate attributes on the opening tag.
        val content = """<tool_call id="abc" type="function">{"name":"date","arguments":{}}</tool_call>"""

        val calls = LocalToolCallParser.resolve(content)

        assertEquals(1, calls.size)
        assertEquals("date", calls[0].name)
    }
}
