package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import java.security.MessageDigest

class HashTool : KoloTool() {
    override val name = "hash"
    override val description = "Compute a hash of a string using MD5, SHA-1, SHA-256, or SHA-512."
    override val parameterSchema = """{"type":"object","properties":{"algorithm":{"type":"string","enum":["md5","sha1","sha256","sha512"],"description":"Hash algorithm"},"input":{"type":"string","description":"Input string to hash"}},"required":["algorithm","input"]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val algorithm = params["algorithm"] ?: return ToolExecutionResult.err("Missing algorithm parameter")
        val input = params["input"] ?: return ToolExecutionResult.err("Missing input parameter")

        val digest = when (algorithm.lowercase()) {
            "md5" -> MessageDigest.getInstance("MD5")
            "sha1" -> MessageDigest.getInstance("SHA-1")
            "sha256" -> MessageDigest.getInstance("SHA-256")
            "sha512" -> MessageDigest.getInstance("SHA-512")
            else -> return ToolExecutionResult.err("Unsupported algorithm: $algorithm")
        }

        val hash = digest.digest(input.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return ToolExecutionResult.ok("$algorithm: $hash")
    }
}