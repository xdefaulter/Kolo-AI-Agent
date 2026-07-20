package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class CalculatorScientificNotationTest {

    private val tool = CalculatorTool()

    private suspend fun exec(expr: String) = tool.execute(mapOf("expression" to expr), ToolExecutionContext(chatId = "test"))

    @Test
    fun scientificNotationLowercaseParses() = runTest {
        val result = exec("1e3")
        assertTrue(result.success)
        assertEquals(1000.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun scientificNotationUppercaseParses() = runTest {
        val result = exec("1E3")
        assertTrue(result.success)
        assertEquals(1000.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun scientificNotationWithFractionalMantissa() = runTest {
        val result = exec("1.5e2")
        assertTrue(result.success)
        assertEquals(150.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun scientificNotationWithPositiveExponent() = runTest {
        val result = exec("2e+3")
        assertTrue(result.success)
        assertEquals(2000.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun scientificNotationWithNegativeExponent() = runTest {
        val result = exec("1e-2")
        assertTrue(result.success)
        assertEquals(0.01, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun scientificNotationMixedWithAddition() = runTest {
        val result = exec("1e3 + 1")
        assertTrue(result.success)
        assertEquals(1001.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun powerOperatorWorks() = runTest {
        val result = exec("2**3")
        assertTrue(result.success)
        assertEquals(8.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun powerIsRightAssociative() = runTest {
        // 2**3**2 = 2**(3**2) = 2**9 = 512
        val result = exec("2**3**2")
        assertTrue(result.success)
        assertEquals(512.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun unaryMinusBindsLooserThanPower() = runTest {
        // -2**2 = -(2**2) = -4
        val result = exec("-2**2")
        assertTrue(result.success)
        assertEquals(-4.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun unaryMinusOnLiteral() = runTest {
        val result = exec("-3")
        assertTrue(result.success)
        assertEquals(-3.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun piConstantWorks() = runTest {
        val result = exec("pi")
        assertTrue(result.success)
        assertEquals(Math.PI, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun eConstantWorks() = runTest {
        // Bare 'e' with no preceding digit is the constant Math.E,
        // not scientific notation.
        val result = exec("e")
        assertTrue(result.success)
        assertEquals(Math.E, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun sqrtFunctionWorks() = runTest {
        val result = exec("sqrt(16)")
        assertTrue(result.success)
        assertEquals(4.0, result.output.trim().toDouble(), 0.0001)
    }

    @Test
    fun sinOfZeroIsZero() = runTest {
        val result = exec("sin(0)")
        assertTrue(result.success)
        assertEquals(0.0, result.output.trim().toDouble(), 0.0001)
    }
}
