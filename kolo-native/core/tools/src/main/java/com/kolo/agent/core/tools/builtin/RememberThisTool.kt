package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.*
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext

class RememberThisTool : KoloTool() {
    override val name = "remember_this"
    override val description = "Save a memory for future recall. Stores important information about the user, preferences, or context."
    override val parameterSchema = """{"type":"object","properties":{"content":{"type":"string","description":"The information to remember"},"kind":{"type":"string","description":"Type of memory (e.g., 'preference', 'fact', 'instruction')"}},"required":["content"]}"""
    override val permission = ToolPermission.sensitive

    var memoryRepository: MemoryRepository? = null

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val content = params["content"] ?: return ToolExecutionResult.err("Missing content parameter")
        val kind = params["kind"] ?: "fact"

        val repo = memoryRepository
            ?: return ToolExecutionResult.ok("Memory system not yet initialized.")

        val memory = Memory(
            kind = kind,
            content = content,
            sourceChatId = ChatId(context.chatId),
        )
        val saved = repo.save(memory)
        return ToolExecutionResult.ok("Remembered: ${saved.content}")
    }
}