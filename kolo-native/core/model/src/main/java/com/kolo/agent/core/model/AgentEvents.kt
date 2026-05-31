package com.kolo.agent.core.model

/**
 * Agent loop events streamed back to the UI.
 */
sealed class AgentEvent {
    data class ThinkingChunk(val thinking: String) : AgentEvent()
    data class ContentChunk(val content: String) : AgentEvent()
    data class TextComplete(val content: String, val wasCancelled: Boolean = false) : AgentEvent()
    data class ToolCallsStart(val calls: List<ResolvedToolCall>) : AgentEvent()
    data class ToolResult(
        val toolName: String,
        val toolCallId: String,
        val result: ToolExecutionResult,
    ) : AgentEvent()

    data class UsageUpdate(val usage: TokenUsage) : AgentEvent()
    data class ToolApprovalRequest(val approval: ToolPermissionApproval) : AgentEvent()
    data class Cancelled(val partialContent: String = "") : AgentEvent()
    data class Error(val error: String) : AgentEvent()
}

data class ResolvedToolCall(
    val id: String,
    val name: String,
    val arguments: String,
)

data class TokenUsage(
    val promptTokens: Int = 0,
    val completionTokens: Int = 0,
    val totalTokens: Int = 0,
)

data class ToolExecutionResult(
    val success: Boolean,
    val output: String,
    val error: String? = null,
    val metadata: Map<String, String> = emptyMap(),
) {
    companion object {
        fun ok(output: String, metadata: Map<String, String> = emptyMap()) =
            ToolExecutionResult(success = true, output = output, metadata = metadata)

        fun err(error: String) =
            ToolExecutionResult(success = false, output = "", error = error)
    }
}

typealias ToolSubLlmCall = suspend (systemPrompt: String, userMessage: String) -> String
typealias ToolRunByName = suspend (toolName: String, params: Map<String, String>) -> ToolExecutionResult

/**
 * Represents a pending tool-permission approval request shown to the user.
 */
data class ToolPermissionApproval(
    val toolName: String,
    val description: String,
    val arguments: String,
    val permission: ToolPermission,
)