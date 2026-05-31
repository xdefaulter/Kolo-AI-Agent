package com.kolo.agent.feature.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kolo.agent.core.agent.AgentLoop
import com.kolo.agent.core.agent.prompt.SystemPromptComposer
import com.kolo.agent.core.database.dao.ChatDao
import com.kolo.agent.core.database.dao.MessageDao
import com.kolo.agent.core.database.entity.toDomain
import com.kolo.agent.core.database.entity.toEntity
import com.kolo.agent.core.model.*
import com.kolo.agent.core.model.api.ApiMessage
import com.kolo.agent.core.providers.ProviderRepository
import com.kolo.agent.core.providers.openai.OpenAiStreamClient
import com.kolo.agent.core.tools.permissions.ToolPermissionStore
import com.kolo.agent.core.tools.registry.ToolRegistry
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.UUID
import javax.inject.Inject
import kotlin.coroutines.resume

data class ChatUiState(
    val messages: List<Message> = emptyList(),
    val chatList: List<Chat> = emptyList(),
    val currentChatId: ChatId? = null,
    val isLoading: Boolean = false,
    val isStreaming: Boolean = false,
    val streamingContent: String = "",
    val streamingThinking: String = "",
    val activeToolCalls: List<ResolvedToolCall> = emptyList(),
    val toolResults: Map<String, ToolExecutionResult> = emptyMap(),
    val tokenUsage: TokenUsage? = null,
    val error: String? = null,
    val activeModel: String? = null,
    val activeProvider: String? = null,
    val pendingApproval: ToolPermissionApproval? = null,
)

/**
 * Sealed hierarchy for the user's response to a tool approval request.
 * - [AllowOnce]: resume the agent loop, do NOT persist any preference change.
 * - [AlwaysAllow]: resume the agent loop, persist alwaysAllow for this tool.
 * - [DenyOnce]: reject this invocation, do NOT persist any preference change.
 * - [Block]: reject this invocation, persist neverAllow for this tool.
 */
sealed class ToolApprovalAction {
    data class AllowOnce(val approval: ToolPermissionApproval) : ToolApprovalAction()
    data class AlwaysAllow(val approval: ToolPermissionApproval) : ToolApprovalAction()
    data class DenyOnce(val approval: ToolPermissionApproval) : ToolApprovalAction()
    data class Block(val approval: ToolPermissionApproval) : ToolApprovalAction()
}

@HiltViewModel
class ChatViewModel @Inject constructor(
    private val chatDao: ChatDao,
    private val messageDao: MessageDao,
    private val providerRep: ProviderRepository,
    private val toolRegistry: ToolRegistry,
    private val streamClient: OpenAiStreamClient,
    private val permStore: ToolPermissionStore,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    private var currentChatId: ChatId? = null
    private var isCancelled = false

    /** Continuation for pending tool approval — resumed by approve/deny actions. */
    private var approvalContinuation: kotlin.coroutines.Continuation<Boolean>? = null

    init {
        viewModelScope.launch {
            // Observe chat list continuously
            chatDao.getAll().let { chats ->
                _uiState.update { it.copy(chatList = chats.map { c -> c.toDomain() }) }
            }
            val provider = providerRep.getActiveProvider()
            provider?.let { p ->
                _uiState.update { it.copy(
                    activeProvider = p.name,
                    activeModel = p.activeModel?.label ?: p.activeModel?.modelId,
                ) }
            }
        }
    }

    private suspend fun loadChatList() {
        val chats = chatDao.getAll().map { it.toDomain() }
        _uiState.update { it.copy(chatList = chats) }
    }

    fun deleteChat(chatId: ChatId) {
        viewModelScope.launch {
            chatDao.deleteById(chatId.value)
            messageDao.deleteForChat(chatId.value)
            if (currentChatId == chatId) {
                currentChatId = null
                _uiState.update { it.copy(currentChatId = null, messages = emptyList()) }
            }
            loadChatList()
        }
    }

    fun loadChat(chatId: ChatId) {
        currentChatId = chatId
        viewModelScope.launch {
            val messages = messageDao.getForChat(chatId.value).map { it.toDomain() }
            _uiState.update { it.copy(currentChatId = chatId, messages = messages) }
        }
    }

    fun newChat(): ChatId {
        val chatId = ChatId(UUID.randomUUID().toString())
        viewModelScope.launch {
            val chat = Chat(id = chatId)
            chatDao.upsert(chat.toEntity())
            currentChatId = chatId
            _uiState.update { it.copy(currentChatId = chatId, messages = emptyList()) }
            loadChatList()
        }
        return chatId
    }

    fun handleApprovalAction(action: ToolApprovalAction) {
        _uiState.update { it.copy(pendingApproval = null) }
        when (action) {
            is ToolApprovalAction.AllowOnce -> {
                // Resume the agent loop (approved) but do NOT persist
                approvalContinuation?.resume(true)
            }
            is ToolApprovalAction.AlwaysAllow -> {
                // Resume the agent loop (approved) AND persist alwaysAllow
                approvalContinuation?.resume(true)
                viewModelScope.launch { permStore.setMode(action.approval.toolName, ToolPermissionMode.alwaysAllow) }
            }
            is ToolApprovalAction.DenyOnce -> {
                // Deny this invocation but do NOT persist
                approvalContinuation?.resume(false)
            }
            is ToolApprovalAction.Block -> {
                // Deny this invocation AND persist neverAllow
                approvalContinuation?.resume(false)
                viewModelScope.launch { permStore.setMode(action.approval.toolName, ToolPermissionMode.neverAllow) }
            }
        }
        approvalContinuation = null
    }

    /** @deprecated Use [handleApprovalAction] instead for precise semantics. */
    fun approveTool(approval: ToolPermissionApproval) = handleApprovalAction(ToolApprovalAction.AlwaysAllow(approval))

    /** @deprecated Use [handleApprovalAction] instead for precise semantics. */
    fun denyTool(approval: ToolPermissionApproval) = handleApprovalAction(ToolApprovalAction.DenyOnce(approval))

    /** @deprecated Use [handleApprovalAction] instead for precise semantics. */
    fun denyAndBlockTool(approval: ToolPermissionApproval) = handleApprovalAction(ToolApprovalAction.Block(approval))

    fun cancelGeneration() {
        isCancelled = true
        _uiState.update { it.copy(isStreaming = false, isLoading = false, pendingApproval = null) }
        approvalContinuation?.resume(false)
        approvalContinuation = null
    }

    fun clearError() { _uiState.update { it.copy(error = null) } }

    fun sendMessage(content: String) {
        if (content.isBlank()) return
        val chatId = currentChatId ?: run {
            val newId = newChat()
            currentChatId = newId
            newId
        }

        viewModelScope.launch {
            isCancelled = false

            val userMsg = Message(chatId = chatId, role = MessageRole.user, content = content)
            messageDao.upsert(userMsg.toEntity())

            val currentMessages = _uiState.value.messages
            if (currentMessages.isEmpty()) {
                chatDao.updateTitle(chatId.value, content.take(50).replace('\n', ' '))
            }

            _uiState.update { it.copy(
                messages = it.messages + userMsg,
                isLoading = true, isStreaming = true,
                streamingContent = "", streamingThinking = "",
                error = null, activeToolCalls = emptyList(), toolResults = emptyMap(),
                pendingApproval = null,
            )}

            try {
                val provider = providerRep.getActiveProvider()
                    ?: throw IllegalStateException("No active provider configured")
                val activeModelId = provider.activeModel?.modelId
                    ?: throw IllegalStateException("No model selected")

                val apiMessages = buildApiMessages(chatId, content)
                val systemPrompt = SystemPromptComposer.compose(
                    enabledTools = toolRegistry.getToolsForProvider(provider).map { it.name },
                )
                val fullMessages = listOf(ApiMessage(role = "system", content = systemPrompt)) + apiMessages

                val agentLoop = AgentLoop(
                    client = streamClient,
                    toolRegistry = toolRegistry,
                    permissionChecker = { toolName ->
                        val tool = toolRegistry.getTool(toolName)
                        val perm = tool?.permission ?: ToolPermission.sensitive
                        permStore.getMode(toolName, perm).first()
                    },
                    approvalCallback = { approval ->
                        _uiState.update { it.copy(pendingApproval = approval) }
                        suspendCancellableCoroutine { cont -> approvalContinuation = cont }
                    },
                )

                agentLoop.run(config = provider, messages = fullMessages, chatId = chatId.value).collect { event ->
                    if (isCancelled) return@collect
                    when (event) {
                        is AgentEvent.ThinkingChunk -> _uiState.update { it.copy(streamingThinking = it.streamingThinking + event.thinking) }
                        is AgentEvent.ContentChunk -> _uiState.update { it.copy(streamingContent = it.streamingContent + event.content) }
                        is AgentEvent.TextComplete -> {
                            val msg = Message(chatId = chatId, role = MessageRole.assistant, content = event.content)
                            messageDao.upsert(msg.toEntity())
                            _uiState.update { it.copy(messages = it.messages + msg, isStreaming = false, isLoading = false, streamingContent = "") }
                        }
                        is AgentEvent.ToolCallsStart -> _uiState.update { it.copy(activeToolCalls = event.calls) }
                        is AgentEvent.ToolResult -> {
                            val newResults = _uiState.value.toolResults.toMutableMap()
                            newResults[event.toolCallId] = event.result
                            val toolMsg = Message(
                                chatId = chatId, role = MessageRole.tool,
                                content = if (event.result.success) event.result.output else "Error: ${event.result.error}",
                                toolCallId = ToolCallId(event.toolCallId), toolName = event.toolName, toolSuccess = event.result.success,
                            )
                            messageDao.upsert(toolMsg.toEntity())
                            _uiState.update { it.copy(toolResults = newResults, messages = it.messages + toolMsg) }
                        }
                        is AgentEvent.ToolApprovalRequest -> { /* handled by approvalCallback suspension */ }
                        is AgentEvent.UsageUpdate -> _uiState.update { it.copy(tokenUsage = event.usage) }
                        is AgentEvent.Cancelled -> _uiState.update { it.copy(isStreaming = false, isLoading = false) }
                        is AgentEvent.Error -> _uiState.update { it.copy(error = event.error, isStreaming = false, isLoading = false) }
                    }
                }
                loadChatList()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message, isStreaming = false, isLoading = false) }
            }
        }
    }

    private suspend fun buildApiMessages(chatId: ChatId, newUserContent: String): List<ApiMessage> {
        val existing = messageDao.getForChat(chatId.value).map { it.toDomain() }
        val messages = existing
            .filter { it.role == MessageRole.user || it.role == MessageRole.assistant || it.role == MessageRole.system || it.role == MessageRole.tool }
            .map { msg ->
                when (msg.role) {
                    MessageRole.tool -> ApiMessage(role = "tool", content = msg.content, toolCallId = msg.toolCallId?.value)
                    else -> ApiMessage(role = msg.role.wire, content = msg.content)
                }
            }.toMutableList()
        if (existing.none { it.content == newUserContent && it.role == MessageRole.user }) {
            messages.add(ApiMessage(role = "user", content = newUserContent))
        }
        return messages
    }
}