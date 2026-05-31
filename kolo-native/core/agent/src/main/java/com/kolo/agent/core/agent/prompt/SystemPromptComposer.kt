package com.kolo.agent.core.agent.prompt

/**
 * Composes the system prompt for each turn of the agent loop.
 */
object SystemPromptComposer {

    private const val BASE_PROMPT = """You are Kolo AI Agent, a helpful chat assistant running directly on the user's device. You have access to skills and approved tools that help with conversation, research, memory, and device actions.

## Your Capabilities
- **Web Search**: Search the internet for information
- **Skills**: Read and follow saved SKILL.md playbooks
- **Calculator**: Perform mathematical calculations
- **Device Tools**: Use approved device capabilities when the user asks

## Guidelines
- Always use tools when they can help complete a task
- Be direct and helpful
- For web searches, synthesize information from multiple results
- If a tool fails, explain why and suggest alternatives
- Never make up information — use tools to verify facts"""

    fun compose(
        memories: List<String> = emptyList(),
        skills: List<String> = emptyList(),
        additionalPrompt: String = "",
        enabledTools: List<String> = emptyList(),
    ): String {
        val parts = mutableListOf(BASE_PROMPT)

        if (memories.isNotEmpty()) {
            parts.add("\n## Memories\n" + memories.joinToString("\n") { "- $it" })
        }

        if (skills.isNotEmpty()) {
            parts.add("\n## Active Skills\n" + skills.joinToString("\n"))
        }

        if (enabledTools.isNotEmpty()) {
            parts.add("\n## Available Tools\n" + enabledTools.joinToString(", "))
        }

        if (additionalPrompt.isNotBlank()) {
            parts.add("\n$additionalPrompt")
        }

        return parts.joinToString("\n")
    }
}