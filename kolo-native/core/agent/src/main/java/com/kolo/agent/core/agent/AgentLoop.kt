package com.kolo.agent.core.agent

import com.kolo.agent.core.model.*
import com.kolo.agent.core.model.api.ApiMessage
import com.kolo.agent.core.model.api.ApiFunctionCall
import com.kolo.agent.core.model.api.ApiToolCall
import com.kolo.agent.core.model.api.ApiToolDefinition
import com.kolo.agent.core.providers.openai.OpenAiStreamClient
import com.kolo.agent.core.agent.parser.StreamingToolCallParser
import com.kolo.agent.core.tools.registry.ToolRegistry
import com.kolo.agent.core.tools.registry.ToolPermissionCheckResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.yield
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

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