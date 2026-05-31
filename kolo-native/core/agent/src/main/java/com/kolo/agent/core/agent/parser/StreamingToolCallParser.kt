package com.kolo.agent.core.agent.parser

import com.kolo.agent.core.model.ResolvedToolCall
import com.kolo.agent.core.providers.openai.ToolCallDelta

/**
 * Accumulates streaming tool-call deltas and resolves them into
 * complete [ResolvedToolCall] objects once the stream finishes.
 */
class StreamingToolCallParser {
    private val callBuffers = mutableMapOf<Int, ToolCallBuffer>()

    fun processDeltas(deltas: List<ToolCallDelta>) {
        for (delta in deltas) {
            val buffer = callBuffers.getOrPut(delta.index) { ToolCallBuffer() }
            delta.id?.let { buffer.id = it }
            delta.name?.let { buffer.name = it }
            delta.argumentsFragment?.let { buffer.arguments.append(it) }
        }
    }

    fun resolve(): List<ResolvedToolCall> {
        return callBuffers.entries
            .sortedBy { it.key }
            .mapNotNull { (_, buf) ->
                val id = buf.id ?: return@mapNotNull null
                val name = buf.name ?: return@mapNotNull null
                ResolvedToolCall(
                    id = id,
                    name = name,
                    arguments = buf.arguments.toString(),
                )
            }
    }

    private class ToolCallBuffer {
        var id: String? = null
        var name: String? = null
        val arguments = StringBuilder()
    }
}