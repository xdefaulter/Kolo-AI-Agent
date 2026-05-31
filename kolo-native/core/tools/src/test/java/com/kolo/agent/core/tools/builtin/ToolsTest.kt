package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.util.Base64

class Base64ToolTest {

    private val tool = Base64Tool()

    @Test
    fun encodeWorks() = runTest {
        val result = tool.execute(
            mapOf("action" to "encode", "input" to "Hello, World!"),
            ToolExecutionContext(chatId = "test"),
        )
        assertTrue(result.success)
        assertTrue(result.output.contains(Base64.getEncoder().encodeToString("Hello, World!".toByteArray())))
    }

    @Test
    fun decodeWorks() = runTest {
        val encoded = Base64.getEncoder().encodeToString("Kolo AI".toByteArray())
        val result = tool.execute(
            mapOf("action" to "decode", "input" to encoded),
            ToolExecutionContext(chatId = "test"),
        )
        assertTrue(result.success)
        assertTrue(result.output.contains("Kolo AI"))
    }

    @Test
    fun invalidActionReturnsError() = runTest {
        val result = tool.execute(
            mapOf("action" to "invalid", "input" to "test"),
            ToolExecutionContext(chatId = "test"),
        )
        assertFalse(result.success)
    }
}

class DateToolTest {

    private val tool = DateTool()

    @Test
    fun returnsCurrentDate() = runTest {
        val result = tool.execute(emptyMap(), ToolExecutionContext(chatId = "test"))
        assertTrue(result.success)
        assertTrue(result.output.isNotEmpty())
    }
}

class HashToolTest {

    private val tool = HashTool()

    @Test
    fun sha256Works() = runTest {
        val result = tool.execute(
            mapOf("algorithm" to "sha256", "input" to "test"),
            ToolExecutionContext(chatId = "test"),
        )
        assertTrue(result.success)
        assertTrue(result.output.contains("sha256"))
    }

    @Test
    fun md5Works() = runTest {
        val result = tool.execute(
            mapOf("algorithm" to "md5", "input" to "test"),
            ToolExecutionContext(chatId = "test"),
        )
        assertTrue(result.success)
        assertTrue(result.output.contains("md5"))
    }

    @Test
    fun unknownAlgorithmReturnsError() = runTest {
        val result = tool.execute(
            mapOf("algorithm" to "unknown", "input" to "test"),
            ToolExecutionContext(chatId = "test"),
        )
        assertFalse(result.success)
    }
}

class JsonParseToolTest {

    private val tool = JsonParseTool()

    @Test
    fun validJsonReturnsFormattedOutput() = runTest {
        val result = tool.execute(
            mapOf("json" to """{"name":"Kolo","version":1}"""),
            ToolExecutionContext(chatId = "test"),
        )
        assertTrue(result.success)
        assertTrue(result.output.contains("name"))
        assertTrue(result.output.contains("Kolo"))
    }

    @Test
    fun invalidJsonReturnsError() = runTest {
        val result = tool.execute(
            mapOf("json" to "not json at all"),
            ToolExecutionContext(chatId = "test"),
        )
        assertFalse(result.success)
    }
}