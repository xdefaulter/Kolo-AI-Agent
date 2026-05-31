package com.kolo.agent.core.agent

import com.kolo.agent.core.model.*
import com.kolo.agent.core.model.api.ApiMessage
import com.kolo.agent.core.model.api.ApiFunctionCall
import com.kolo.agent.core.model.api.ApiToolCall
import com.kolo.agent.core.model.api.ApiToolDefinition
import com.kolo.agent.core.providers.openai.OpenAiStreamClient
import com.kolo.agent.core.providers.local.LlmEngineFactory
import com.kolo.agent.core.agent.parser.StreamingToolCallParser
import com.kolo.agent.core.tools.registry.ToolRegistry
import com.kolo.agent.core.tools.registry.ToolPermissionCheckResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.yield
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.coroutines.resume

/**
 * The core agent think-act-observe loop.
 *
 * Sends typed [ApiMessage]s to the LLM, processes tool calls,
 * feeds results back, and yields [AgentEvent]s to the UI layer.
 *
 * When a tool requires approval (sensitive/dangerous), the loop emits
 * [AgentEvent.ToolApprovalRequest] and suspends until the UI resumes it
 * via the provided [approvalCallback].
 */
class AgentLoop(
    private val client: OpenAiStreamClient,
    private val toolRegistry: ToolRegistry,
    private val permissionChecker: suspend (toolName: String) -> ToolPermissionMode = { ToolPermissionMode.alwaysAllow },
    private val approvalCallback: suspend (ToolPermissionApproval) -> Boolean = { true },
    private val maxIterations: Int = 20,
) {
    /**
     * Run the agent loop. Yields events for content chunks, tool calls,
     * tool results, approval requests, and completion/error states.
     */
    fun run(
        config: ProviderConfig,
        messages: List<ApiMessage>,
        chatId: String,
        additionalSystemPrompt: String = "",
        cancelled: () -> Boolean = { false },
    ): Flow<AgentEvent> = flow {
        if (config.isLocal) {
            runLocalAgent(config, messages, chatId, cancelled)
            return@flow
        }

        var currentMessages = messages.toMutableList()
        var iterations = 0

        // Build tool definitions for this provider
        val toolDefinitions = toolRegistry.getToolDefinitionsForProvider(config)

        while (iterations < maxIterations && !cancelled()) {
            iterations++
            yield()

            val parser = StreamingToolCallParser()
            val contentBuffer = StringBuilder()
            var finishReason: String? = null

            var streamError: String? = null

            try {
                client.chatStream(
                    config = config,
                    messages = currentMessages,
                    tools = if (toolDefinitions.isNotEmpty()) toolDefinitions else null,
                ).collect { chunk ->
                    if (cancelled()) return@collect

                    if (chunk.error != null) {
                        streamError = chunk.error
                        return@collect
                    }

                    if (chunk.content.isNotEmpty()) {
                        contentBuffer.append(chunk.content)
                        emit(AgentEvent.ContentChunk(chunk.content))
                    }

                    chunk.reasoningContent?.let {
                        emit(AgentEvent.ThinkingChunk(it))
                    }

                    chunk.toolCalls?.let { deltas ->
                        parser.processDeltas(deltas)
                    }

                    chunk.usage?.let { usage ->
                        emit(AgentEvent.UsageUpdate(
                            TokenUsage(
                                promptTokens = usage.promptTokens,
                                completionTokens = usage.completionTokens,
                                totalTokens = usage.totalTokens,
                            )
                        ))
                    }

                    chunk.finishReason?.let { reason ->
                        finishReason = reason
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (cancelled()) {
                    val partial = contentBuffer.toString()
                    if (partial.isNotEmpty()) {
                        emit(AgentEvent.TextComplete(partial, wasCancelled = true))
                    }
                    emit(AgentEvent.Cancelled(partial))
                    return@flow
                }
                emit(AgentEvent.Error("API error: ${e.message}"))
                return@flow
            }

            // Check for stream-level errors
            streamError?.let {
                emit(AgentEvent.Error(it))
                return@flow
            }

            val fullContent = contentBuffer.toString()

            if (cancelled()) {
                if (fullContent.isNotEmpty()) {
                    emit(AgentEvent.TextComplete(fullContent, wasCancelled = true))
                }
                emit(AgentEvent.Cancelled(fullContent))
                return@flow
            }

            val resolvedCalls = parser.resolve()

            // No tool calls — text completion
            if (resolvedCalls.isEmpty()) {
                if (fullContent.isNotEmpty()) {
                    emit(AgentEvent.TextComplete(fullContent))
                }
                return@flow
            }

            // Add assistant message with proper tool_calls in OpenAI format
            currentMessages.add(ApiMessage(
                role = "assistant",
                content = fullContent.ifBlank { null },
                toolCalls = resolvedCalls.map { call ->
                    ApiToolCall(
                        id = call.id,
                        type = "function",
                        function = ApiFunctionCall(
                            name = call.name,
                            arguments = call.arguments,
                        )
                    )
                },
            ))

            emit(AgentEvent.ToolCallsStart(resolvedCalls))

            if (cancelled()) {
                emit(AgentEvent.Cancelled(fullContent))
                return@flow
            }

            // Execute tools with permission gating
            for (call in resolvedCalls) {
                if (cancelled()) {
                    emit(AgentEvent.Cancelled(fullContent))
                    return@flow
                }

                // Check tool permission
                val tool = toolRegistry.getTool(call.name)
                val permResult = if (tool != null) {
                    val mode = permissionChecker(call.name)
                    when {
                        ToolPermissionStore_companion.canAutoApprove(mode) -> ToolPermissionCheckResult.Allowed
                        ToolPermissionStore_companion.isBlocked(mode) -> ToolPermissionCheckResult.Blocked("Tool '${call.name}' is set to never allow")
                        else -> ToolPermissionCheckResult.NeedsApproval(tool.permission)
                    }
                } else {
                    ToolPermissionCheckResult.Allowed // Unknown tools just go through (or return error below)
                }

                when (permResult) {
                    is ToolPermissionCheckResult.Allowed -> {
                        // Execute directly
                        val result = toolRegistry.executeTool(
                            name = call.name,
                            arguments = call.arguments,
                            chatId = chatId,
                            providerConfig = config,
                        )
                        emit(AgentEvent.ToolResult(call.name, call.id, result))
                        currentMessages.add(ApiMessage(
                            role = "tool",
                            content = if (result.success) result.output else "Error: ${result.error}",
                            toolCallId = call.id,
                        ))
                    }
                    is ToolPermissionCheckResult.NeedsApproval -> {
                        // Emit approval request and wait for user decision
                        val approval = ToolPermissionApproval(
                            toolName = call.name,
                            description = tool?.description ?: call.name,
                            arguments = call.arguments,
                            permission = permResult.permission,
                        )
                        emit(AgentEvent.ToolApprovalRequest(approval))

                        val approved = approvalCallback(approval)
                        if (!approved) {
                            val result = ToolExecutionResult.err("Tool '${call.name}' was denied by user")
                            emit(AgentEvent.ToolResult(call.name, call.id, result))
                            currentMessages.add(ApiMessage(
                                role = "tool",
                                content = "Error: User denied permission for tool '${call.name}'",
                                toolCallId = call.id,
                            ))
                        } else {
                            val result = toolRegistry.executeTool(
                                name = call.name,
                                arguments = call.arguments,
                                chatId = chatId,
                                providerConfig = config,
                            )
                            emit(AgentEvent.ToolResult(call.name, call.id, result))
                            currentMessages.add(ApiMessage(
                                role = "tool",
                                content = if (result.success) result.output else "Error: ${result.error}",
                                toolCallId = call.id,
                            ))
                        }
                    }
                    is ToolPermissionCheckResult.Blocked -> {
                        val result = ToolExecutionResult.err(permResult.reason)
                        emit(AgentEvent.ToolResult(call.name, call.id, result))
                        currentMessages.add(ApiMessage(
                            role = "tool",
                            content = "Error: ${permResult.reason}",
                            toolCallId = call.id,
                        ))
                    }
                }
            }
        }

        if (cancelled()) {
            emit(AgentEvent.Cancelled(""))
        } else {
            emit(AgentEvent.Error("Max iterations reached ($maxIterations)"))
        }
    }

    private suspend fun FlowCollector<AgentEvent>.runLocalAgent(
        config: ProviderConfig,
        messages: List<ApiMessage>,
        chatId: String,
        cancelled: () -> Boolean,
    ) {
        val modelPath = config.modelPath
        if (modelPath.isNullOrBlank()) {
            emit(AgentEvent.Error("Local llama.cpp provider requires a GGUF modelPath."))
            return
        }

        val localEngine = LlmEngineFactory.create(config)
        val currentMessages = messages.toMutableList()
        val toolDefinitions = toolRegistry.getToolDefinitionsForProvider(config)

        try {
            localEngine.loadModel(
                modelPath = modelPath,
                contextSize = config.activeModel?.contextWindow ?: 4096,
                threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 8),
            )

            repeat(maxIterations) {
                if (cancelled()) {
                    emit(AgentEvent.Cancelled(""))
                    return
                }
                yield()

                val prompt = buildLocalPrompt(currentMessages, toolDefinitions)
                val completion = collectLocalCompletion(
                    engine = localEngine,
                    prompt = prompt,
                    config = config,
                )
                val rawContent = completion.content

                if (cancelled()) {
                    emit(AgentEvent.Cancelled(rawContent))
                    return
                }

                val resolvedCalls = LocalToolCallParser.resolve(rawContent)
                if (resolvedCalls.isEmpty()) {
                    val finalContent = LocalToolCallParser.stripToolCalls(rawContent).trim()
                    if (finalContent.isNotEmpty()) {
                        if (!completion.streamedToUi) {
                            emit(AgentEvent.ContentChunk(finalContent))
                        }
                        emit(AgentEvent.TextComplete(finalContent))
                    }
                    return
                }

                emit(AgentEvent.ToolCallsStart(resolvedCalls))
                currentMessages.add(ApiMessage(
                    role = "assistant",
                    content = null,
                    toolCalls = resolvedCalls.map { call ->
                        ApiToolCall(
                            id = call.id,
                            type = "function",
                            function = ApiFunctionCall(
                                name = call.name,
                                arguments = call.arguments,
                            ),
                        )
                    },
                ))

                for (call in resolvedCalls) {
                    if (cancelled()) {
                        emit(AgentEvent.Cancelled(rawContent))
                        return
                    }

                    val tool = toolRegistry.getTool(call.name)
                    val permResult = if (tool != null) {
                        val mode = permissionChecker(call.name)
                        when {
                            ToolPermissionStore_companion.canAutoApprove(mode) -> ToolPermissionCheckResult.Allowed
                            ToolPermissionStore_companion.isBlocked(mode) -> ToolPermissionCheckResult.Blocked("Tool '${call.name}' is set to never allow")
                            else -> ToolPermissionCheckResult.NeedsApproval(tool.permission)
                        }
                    } else {
                        ToolPermissionCheckResult.Allowed
                    }

                    val result = when (permResult) {
                        is ToolPermissionCheckResult.Allowed -> toolRegistry.executeTool(
                            name = call.name,
                            arguments = call.arguments,
                            chatId = chatId,
                            providerConfig = config,
                        )
                        is ToolPermissionCheckResult.NeedsApproval -> {
                            val approval = ToolPermissionApproval(
                                toolName = call.name,
                                description = tool?.description ?: call.name,
                                arguments = call.arguments,
                                permission = permResult.permission,
                            )
                            emit(AgentEvent.ToolApprovalRequest(approval))
                            if (approvalCallback(approval)) {
                                toolRegistry.executeTool(
                                    name = call.name,
                                    arguments = call.arguments,
                                    chatId = chatId,
                                    providerConfig = config,
                                )
                            } else {
                                ToolExecutionResult.err("Tool '${call.name}' was denied by user")
                            }
                        }
                        is ToolPermissionCheckResult.Blocked -> ToolExecutionResult.err(permResult.reason)
                    }

                    emit(AgentEvent.ToolResult(call.name, call.id, result))
                    currentMessages.add(ApiMessage(
                        role = "tool",
                        content = if (result.success) result.output else "Error: ${result.error}",
                        toolCallId = call.id,
                    ))
                }
            }

            emit(AgentEvent.Error("Max iterations reached ($maxIterations)"))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(AgentEvent.Error("Local llama.cpp error: ${e.message}"))
        } finally {
            localEngine.unloadModel()
        }
    }

    private suspend fun FlowCollector<AgentEvent>.collectLocalCompletion(
        engine: com.kolo.agent.core.providers.local.LocalLlmEngine,
        prompt: String,
        config: ProviderConfig,
    ): LocalCompletion {
        val raw = StringBuilder()
        val pending = StringBuilder()
        var decided = false
        var withholding = true
        var streamed = false

        engine.completeStream(
            prompt = prompt,
            maxTokens = config.activeModel?.maxTokens ?: 1024,
            temperature = (config.activeModel?.temperature ?: 0.7).toFloat(),
        ).collect { token ->
            raw.append(token)
            if (!decided) {
                pending.append(token)
                val trimmed = pending.toString().trimStart()
                when {
                    trimmed.isEmpty() -> Unit
                    trimmed.startsWith("<tool_call") ||
                        trimmed.startsWith("```tool_call") ||
                        trimmed.startsWith("{") -> Unit
                    else -> {
                        decided = true
                        withholding = false
                        val chunk = pending.toString()
                        pending.clear()
                        streamed = true
                        emit(AgentEvent.ContentChunk(chunk))
                    }
                }
            } else if (!withholding) {
                streamed = true
                emit(AgentEvent.ContentChunk(token))
            }
        }

        return LocalCompletion(
            content = raw.toString(),
            streamedToUi = streamed,
        )
    }

    private fun buildLocalPrompt(
        messages: List<ApiMessage>,
        toolDefinitions: List<ApiToolDefinition>,
    ): String {
        val builder = StringBuilder()
        builder.appendLine("You are Kolo AI Agent running locally with llama.cpp.")
        builder.appendLine("Answer directly unless a tool is needed.")
        if (toolDefinitions.isNotEmpty()) {
            builder.appendLine()
            builder.appendLine("When a tool is needed, output exactly one tool call and no prose:")
            builder.appendLine("""<tool_call>{"name":"calculator","arguments":{"expression":"2+2"}}</tool_call>""")
            builder.appendLine("After a tool result is provided, answer the user normally.")
            builder.appendLine()
            builder.appendLine("Available tools:")
            toolDefinitions.forEach { def ->
                builder.append("- ")
                    .append(def.function.name)
                    .append(": ")
                    .append(def.function.description)
                    .append(" Parameters: ")
                    .append(def.function.parameters)
                    .appendLine()
            }
        }
        builder.appendLine()
        builder.appendLine("Conversation:")
        messages.forEach { msg ->
            val role = when (msg.role) {
                "tool" -> "TOOL_RESULT ${msg.toolCallId.orEmpty()}"
                else -> msg.role.uppercase()
            }
            builder.append(role).append(": ").appendLine(msg.content.orEmpty())
        }
        builder.append("ASSISTANT:")
        return builder.toString()
    }

    private data class LocalCompletion(
        val content: String,
        val streamedToUi: Boolean,
    )
}

private object LocalToolCallParser {
    private val json = Json { ignoreUnknownKeys = true }
    private val blockPatterns = listOf(
        Regex("""(?s)<tool_call>\s*(\{.*?})\s*</tool_call>"""),
        Regex("""(?s)```tool_call\s*(\{.*?})\s*```"""),
    )

    fun resolve(content: String): List<ResolvedToolCall> {
        val calls = mutableListOf<ResolvedToolCall>()
        for (pattern in blockPatterns) {
            pattern.findAll(content).forEach { match ->
                parsePayload(match.groupValues[1], calls.size)?.let { calls.add(it) }
            }
        }
        if (calls.isEmpty()) {
            parsePayload(content.trim(), 0)?.let { calls.add(it) }
        }
        return calls
    }

    fun stripToolCalls(content: String): String {
        return blockPatterns.fold(content) { acc, pattern -> pattern.replace(acc, "") }
    }

    private fun parsePayload(payload: String, index: Int): ResolvedToolCall? {
        return try {
            val obj = json.parseToJsonElement(payload).jsonObject
            val name = obj["name"]?.jsonPrimitive?.contentOrNull
                ?: obj["tool_name"]?.jsonPrimitive?.contentOrNull
                ?: return null
            val argumentsElement = obj["arguments"] ?: obj["params"]
            val arguments = when (argumentsElement) {
                null -> "{}"
                is JsonObject -> argumentsElement.toString()
                else -> argumentsElement.jsonPrimitive.contentOrNull ?: argumentsElement.toString()
            }
            ResolvedToolCall(
                id = "local_tool_${System.currentTimeMillis()}_$index",
                name = name,
                arguments = arguments,
            )
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Companion helpers for permission checking — extracted to avoid a runtime
 * dependency on the Android context-requiring ToolPermissionStore in the agent loop.
 */
internal object ToolPermissionStore_companion {
    fun canAutoApprove(mode: ToolPermissionMode): Boolean =
        mode == ToolPermissionMode.alwaysAllow

    fun isBlocked(mode: ToolPermissionMode): Boolean =
        mode == ToolPermissionMode.neverAllow
}
