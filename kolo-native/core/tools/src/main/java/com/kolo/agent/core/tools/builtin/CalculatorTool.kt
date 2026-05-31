package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext

class CalculatorTool : KoloTool() {
    override val name = "calculator"
    override val description = "Evaluate mathematical expressions. Supports +, -, *, /, parentheses, and common math functions (sqrt, sin, cos, tan, log, abs, pi, e)."
    override val parameterSchema = """{"type":"object","properties":{"expression":{"type":"string","description":"Mathematical expression to evaluate"}},"required":["expression"]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val expr = params["expression"] ?: return ToolExecutionResult.err("Missing expression parameter")
        return try {
            val result = evalMath(expr)
            ToolExecutionResult.ok(result)
        } catch (e: Exception) {
            ToolExecutionResult.err("Calculation error: ${e.message}")
        }
    }

    /**
     * Simple recursive-descent math evaluator. No javax.script dependency.
     * Supports: +, -, *, /, ^, parentheses, and functions: sqrt, sin, cos, tan, log, abs, pi, e
     */
    private fun evalMath(expr: String): String {
        val sanitized = expr.lowercase()
            .replace("×", "*")
            .replace("÷", "/")
            .replace("π", Math.PI.toString())
            .replace("^", "**") // We'll handle ** as power

        val parser = MathParser(sanitized)
        val result = parser.parse()
        return result.toString()
    }

    private class MathParser(private val input: String) {
        private var pos = 0

        fun parse(): Double {
            val result = parseExpression()
            if (pos < input.length) {
                throw IllegalArgumentException("Unexpected character: ${input[pos]}")
            }
            return result
        }

        private fun parseExpression(): Double {
            var result = parseTerm()
            while (pos < input.length) {
                skipWhitespace()
                when {
                    pos < input.length && input[pos] == '+' -> { pos++; result += parseTerm() }
                    pos < input.length && input[pos] == '-' -> { pos++; result -= parseTerm() }
                    else -> break
                }
            }
            return result
        }

        private fun parseTerm(): Double {
            var result = parsePower()
            while (pos < input.length) {
                skipWhitespace()
                when {
                    pos < input.length && input[pos] == '*' && (pos + 1 >= input.length || input[pos + 1] != '*') -> { pos++; result *= parsePower() }
                    pos < input.length && input[pos] == '/' -> { pos++; result /= parsePower() }
                    else -> break
                }
            }
            return result
        }

        private fun parsePower(): Double {
            var result = parseUnary()
            skipWhitespace()
            if (pos + 1 < input.length && input[pos] == '*' && input[pos + 1] == '*') {
                pos += 2 // skip **
                result = Math.pow(result, parsePower())
            }
            return result
        }

        private fun parseUnary(): Double {
            if (pos < input.length && input[pos] == '-') {
                pos++
                return -parseAtom()
            }
            if (pos < input.length && input[pos] == '+') {
                pos++
            }
            return parseAtom()
        }

        private fun parseAtom(): Double {
            skipWhitespace()

            // Parentheses
            if (pos < input.length && input[pos] == '(') {
                pos++
                val result = parseExpression()
                if (pos < input.length && input[pos] == ')') pos++
                return result
            }

            // Functions
            val functions = mapOf(
                "sqrt" to { x: Double -> Math.sqrt(x) },
                "sin" to { x: Double -> Math.sin(x) },
                "cos" to { x: Double -> Math.cos(x) },
                "tan" to { x: Double -> Math.tan(x) },
                "log" to { x: Double -> Math.log10(x) },
                "ln" to { x: Double -> Math.log(x) },
                "abs" to { x: Double -> Math.abs(x) },
                "ceil" to { x: Double -> Math.ceil(x) },
                "floor" to { x: Double -> Math.floor(x) },
            )

            for ((name, fn) in functions) {
                if (input.startsWith(name, pos)) {
                    pos += name.length
                    skipWhitespace()
                    if (pos < input.length && input[pos] == '(') {
                        pos++
                        val arg = parseExpression()
                        if (pos < input.length && input[pos] == ')') pos++
                        return fn(arg)
                    }
                }
            }

            // Constants
            if (input.startsWith("pi", pos)) {
                pos += 2
                return Math.PI
            }
            if (pos < input.length && input[pos] == 'e' &&
                (pos + 1 >= input.length || !input[pos + 1].isLetter())) {
                pos++
                return Math.E
            }

            // Number
            val start = pos
            while (pos < input.length && (input[pos].isDigit() || input[pos] == '.')) {
                pos++
            }
            if (pos > start) {
                return input.substring(start, pos).toDouble()
            }

            throw IllegalArgumentException("Unexpected character at position $pos: ${if (pos < input.length) input[pos] else "end"}")
        }

        private fun skipWhitespace() {
            while (pos < input.length && input[pos].isWhitespace()) pos++
        }
    }
}