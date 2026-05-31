package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.*
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext

class RecallMemoriesTool : KoloTool() {
    override val name = "recall_memories"
    override val description = "Search and recall relevant memories. Returns memories that match the query."
    override val parameterSchema = """{"type":"object","properties":{"query":{"type":"string","description":"Search query for memories"},"limit":{"type":"integer","description":"Maximum number of memories to return (default: 6)"}},"required":["query"]}"""
    override val permission = ToolPermission.safe

    var memoryRepository: MemoryRepository? = null

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val query = params["query"] ?: return ToolExecutionResult.err("Missing query parameter")
        val limit = params["limit"]?.toIntOrNull() ?: 6

        val repo = memoryRepository
            ?: return ToolExecutionResult.ok("Memory system not yet initialized.")

        val memories = repo.search(query, limit)
        if (memories.isEmpty()) {
            return ToolExecutionResult.ok("No relevant memories found for '$query'.")
        }

        val result = memories.mapIndexed { i, m ->
            "${i + 1}. [${m.kind}] ${m.content}"
        }.joinToString("\n")

        repo.touchBatch(memories.map { it.id.value })

        return ToolExecutionResult.ok("Found ${memories.size} relevant memories:\n$result")
    }
}