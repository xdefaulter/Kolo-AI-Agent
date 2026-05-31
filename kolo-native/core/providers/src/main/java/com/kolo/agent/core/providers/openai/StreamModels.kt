package com.kolo.agent.core.providers.openai

import kotlinx.serialization.Serializable

/**
 * SSE chunk from an OpenAI-compatible streaming endpoint.
 */
@Serializable
data class StreamChunk(
    val content: String = "",
    val toolCalls: List<ToolCallDelta>? = null,
    val reasoningContent: String? = null,
    val finishReason: String? = null,
    val error: String? = null,
    val usage: UsageInfo? = null,
)

@Serializable
data class ToolCallDelta(
    val index: Int,
    val id: String? = null,
    val name: String? = null,
    val argumentsFragment: String? = null,
)

@Serializable
data class UsageInfo(
    val promptTokens: Int = 0,
    val completionTokens: Int = 0,
    val totalTokens: Int = 0,
)