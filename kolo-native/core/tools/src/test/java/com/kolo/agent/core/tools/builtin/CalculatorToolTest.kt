package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class CalculatorToolTest {

    private val tool = CalculatorTool()

    private suspend fun exec(expr: String) = tool.execute(mapOf("expression" to expr), ToolExecutionContext(chatId = "test"))

    @Test
    fun additionWorks() = runTest {
        val result = exec("2 + 3")
        assertTrue(result.success)
        assertEquals(5.0, result.output.trim().toDouble(), 0.001)
    }

    @Test
    fun subtractionWorks() = runTest {
        val result = exec("10 - 4")
        assertTrue(result.success)
        assertEquals(6.0, result.output.trim().toDouble(), 0.001)
    }

    @Test
    fun multiplicationWorks() = runTest {
        val result = exec("3 * 7")
        assertTrue(result.success)
        assertEquals(21.0, result.output.trim().toDouble(), 0.001)
    }

    @Test
    fun divisionWorks() = runTest {
        val result = exec("20 / 4")
        assertTrue(result.success)
        assertEquals(5.0, result.output.trim().toDouble(), 0.001)
    }

    @Test
    fun complexExpressionWorks() = runTest {
        val result = exec("2 + 3 * 4")
        assertTrue(result.success)
        assertEquals(14.0, result.output.trim().toDouble(), 0.001)
    }

    @Test
    fun parenthesesWork() = runTest {
        val result = exec("(2 + 3) * 4")
        assertTrue(result.success)
        assertEquals(20.0, result.output.trim().toDouble(), 0.001)
    }

    @Test
    fun invalidExpressionReturnsError() = runTest {
        val result = exec("abc")
        assertFalse(result.success)
    }

    @Test
    fun missingExpressionReturnsError() = runTest {
        val result = tool.execute(emptyMap(), ToolExecutionContext(chatId = "test"))
        assertFalse(result.success)
    }

    @Test
    fun divisionByZeroReturnsInfinity() = runTest {
        val result = exec("10 / 0")
        // Kotlin double division by zero produces Infinity, not an error
        assertTrue(result.success)
        assertTrue(result.output.contains("Infinity") || result.output.contains("∞"))
    }
}