package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import java.util.Base64 as JavaBase64

class Base64Tool : KoloTool() {
    override val name = "base64"
    override val description = "Encode or decode Base64 strings."
    override val parameterSchema = """{"type":"object","properties":{"action":{"type":"string","enum":["encode","decode"],"description":"Whether to encode or decode"},"input":{"type":"string","description":"The string to encode or decode"}},"required":["action","input"]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val action = params["action"] ?: params["operation"] ?: return ToolExecutionResult.err("Missing action parameter")
        val input = params["input"] ?: return ToolExecutionResult.err("Missing input parameter")

        return when (action.lowercase()) {
            "encode" -> {
                val encoded = JavaBase64.getEncoder().encodeToString(input.toByteArray())
                ToolExecutionResult.ok(encoded)
            }
            "decode" -> {
                try {
                    val decoded = String(JavaBase64.getDecoder().decode(input))
                    ToolExecutionResult.ok(decoded)
                } catch (e: Exception) {
                    ToolExecutionResult.err("Base64 decode error: ${e.message}")
                }
            }
            else -> ToolExecutionResult.err("Invalid action: $action. Use 'encode' or 'decode'.")
        }
    }
}