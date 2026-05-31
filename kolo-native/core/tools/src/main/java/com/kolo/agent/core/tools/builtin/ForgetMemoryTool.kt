package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.MemoryRepository
import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext

class ForgetMemoryTool : KoloTool() {
    override val name = "forget_memory"
    override val description = "Delete a previously stored memory by its ID."
    override val parameterSchema = """{"type":"object","properties":{"memory_id":{"type":"string","description":"The ID of the memory to delete"}},"required":["memory_id"]}"""
    override val permission = ToolPermission.dangerous

    var memoryRepository: MemoryRepository? = null

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val memoryId = params["memory_id"] ?: return ToolExecutionResult.err("Missing memory_id parameter")

        val repo = memoryRepository
            ?: return ToolExecutionResult.ok("Memory system not yet initialized.")

        repo.deleteById(memoryId)
        return ToolExecutionResult.ok("Memory $memoryId has been forgotten.")
    }
}