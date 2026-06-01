package com.kolo.agent.feature.chat

import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kolo.agent.core.agent.AgentLoop
import com.kolo.agent.core.agent.prompt.SystemPromptComposer
import com.kolo.agent.core.database.dao.ChatDao
import com.kolo.agent.core.database.dao.FolderDao
import com.kolo.agent.core.database.dao.MessageDao
import com.kolo.agent.core.database.dao.PromptTemplateDao
import com.kolo.agent.core.database.entity.toDomain
import com.kolo.agent.core.database.entity.toEntity
import com.kolo.agent.core.database.repository.RoomMemoryRepository
import com.kolo.agent.core.model.*
import com.kolo.agent.core.model.api.ApiContentPart
import com.kolo.agent.core.model.api.ApiMessage
import com.kolo.agent.core.providers.ProviderRepository
import com.kolo.agent.core.providers.local.LocalModelManager
import com.kolo.agent.core.providers.openai.OpenAiStreamClient
import com.kolo.agent.core.settings.AppSettings
import com.kolo.agent.core.tools.permissions.ToolPermissionStore
import com.kolo.agent.core.tools.registry.ToolRegistry
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
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
    val activeProviderConfig: ProviderConfig? = null,
    val promptTemplates: List<PromptTemplate> = emptyList(),
    val folders: List<Folder> = emptyList(),
    val activeFolderId: FolderId? = null,
    val chatSearchQuery: String = "",
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
    private val folderDao: FolderDao,
    private val promptTemplateDao: PromptTemplateDao,
    private val providerRep: ProviderRepository,
    private val toolRegistry: ToolRegistry,
    private val streamClient: OpenAiStreamClient,
    private val permStore: ToolPermissionStore,
    private val appSettings: AppSettings,
    private val localModelManager: LocalModelManager,
    private val memoryRepository: RoomMemoryRepository,
    @ApplicationContext private val androidContext: Context,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    private var currentChatId: ChatId? = null
    private var isCancelled = false

    /** Continuation for pending tool approval — resumed by approve/deny actions. */
    private var approvalContinuation: kotlin.coroutines.Continuation<Boolean>? = null

    init {
        viewModelScope.launch {
            loadFolders()
            loadChatList()
        }
        viewModelScope.launch {
            providerRep.activeProviderFlow.collect { provider ->
                _uiState.update {
                    it.copy(
                        activeProvider = provider?.name,
                        activeModel = provider?.displayModelName(),
                        activeProviderConfig = provider,
                    )
                }
            }
        }
        viewModelScope.launch {
            loadPromptTemplates()
        }
        viewModelScope.launch {
            appSettings.customTools.collect { toolRegistry.setCustomTools(it) }
        }
        viewModelScope.launch {
            appSettings.skills.collect { toolRegistry.setSkills(it) }
        }
    }

    private suspend fun loadChatList() {
        val folderId = _uiState.value.activeFolderId
        val query = _uiState.value.chatSearchQuery.trim().lowercase()
        val matchingChatIds = if (query.isBlank()) {
            emptySet()
        } else {
            messageDao.searchAll("%$query%", limit = 100)
                .map { it.chat_id }
                .toSet()
        }
        val chats = chatDao.getAll().map { it.toDomain() }
            .filter { folderId == null || it.folderId == folderId }
            .filter { query.isBlank() || it.title.lowercase().contains(query) || it.id.value in matchingChatIds }
        _uiState.update { it.copy(chatList = chats) }
    }

    private suspend fun loadFolders() {
        _uiState.update { state ->
            state.copy(folders = folderDao.getAll().map { it.toDomain() })
        }
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
            val chat = Chat(id = chatId, folderId = _uiState.value.activeFolderId)
            chatDao.upsert(chat.toEntity())
            currentChatId = chatId
            _uiState.update { it.copy(currentChatId = chatId, messages = emptyList()) }
            loadChatList()
        }
        return chatId
    }

    fun setChatSearchQuery(query: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(chatSearchQuery = query) }
            loadChatList()
        }
    }

    fun setActiveFolder(folderId: FolderId?) {
        viewModelScope.launch {
            _uiState.update { it.copy(activeFolderId = folderId) }
            loadChatList()
        }
    }

    fun createFolder(name: String) {
        val cleanName = name.trim()
        if (cleanName.isBlank()) return
        viewModelScope.launch {
            folderDao.upsert(Folder(name = cleanName).toEntity())
            loadFolders()
            loadChatList()
        }
    }

    fun deleteFolder(folderId: FolderId) {
        viewModelScope.launch {
            folderDao.deleteById(folderId.value)
            if (_uiState.value.activeFolderId == folderId) {
                _uiState.update { it.copy(activeFolderId = null) }
            }
            loadFolders()
            loadChatList()
        }
    }

    fun moveChat(chatId: ChatId, folderId: FolderId?) {
        viewModelScope.launch {
            chatDao.moveChatToFolder(chatId.value, folderId?.value)
            loadChatList()
        }
    }

    fun setPinned(chatId: ChatId, pinned: Boolean) {
        viewModelScope.launch {
            chatDao.setPinned(chatId.value, pinned)
            loadChatList()
        }
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

    fun setActiveModel(modelId: String) {
        val provider = _uiState.value.activeProviderConfig ?: return
        viewModelScope.launch {
            providerRep.setActiveModel(provider.id, modelId)
        }
    }

    fun refreshActiveProviderModels() {
        val provider = _uiState.value.activeProviderConfig ?: return
        if (provider.isLocal) return
        viewModelScope.launch {
            try {
                val fetched = streamClient.fetchModels(provider)
                    .distinctBy { it.first }
                    .sortedBy { it.first }
                if (fetched.isEmpty()) {
                    _uiState.update { it.copy(error = "No models were returned by ${provider.effectiveModelsUrl}") }
                    return@launch
                }
                val activeModelId = provider.activeModel?.modelId
                val updated = provider.copy(
                    models = fetched.mapIndexed { index, (id, label) ->
                        ModelConfig(
                            modelId = id,
                            displayName = label?.takeIf { it.isNotBlank() && it != id },
                            isActive = id == activeModelId || (activeModelId == null && index == 0),
                        )
                    },
                    updatedAt = System.currentTimeMillis(),
                )
                providerRep.saveProvider(updated, providerRep.getApiKey(provider.id.value))
            } catch (e: Exception) {
                _uiState.update { it.copy(error = "Model fetch failed: ${e.message ?: "unknown error"}") }
            }
        }
    }

    fun touchPromptTemplate(templateId: TemplateId) {
        viewModelScope.launch {
            promptTemplateDao.touch(templateId.value)
            loadPromptTemplates()
        }
    }

    fun sendMessage(content: String, attachments: List<MessageAttachment> = emptyList()) {
        if (content.isBlank() && attachments.isEmpty()) return
        if (_uiState.value.isStreaming) return
        val chatId = currentChatId ?: run {
            val newId = newChat()
            currentChatId = newId
            newId
        }

        viewModelScope.launch {
            isCancelled = false
            val stableAttachments = persistAttachments(attachments)
            if (chatDao.getById(chatId.value) == null) {
                chatDao.upsert(Chat(id = chatId, folderId = _uiState.value.activeFolderId).toEntity())
            }

            val userMsg = Message(chatId = chatId, role = MessageRole.user, content = content, attachments = stableAttachments)
            messageDao.upsert(userMsg.toEntity())

            val currentMessages = _uiState.value.messages
            if (currentMessages.isEmpty()) {
                chatDao.updateTitle(chatId.value, firstChatTitle(content, stableAttachments))
            }

            _uiState.update { it.copy(
                messages = it.messages + userMsg,
                isLoading = true, isStreaming = true,
                streamingContent = "", streamingThinking = "",
                error = null, activeToolCalls = emptyList(), toolResults = emptyMap(),
                pendingApproval = null,
            )}

            try {
                val rawProvider = providerRep.getActiveProvider()
                    ?: throw IllegalStateException("No active provider configured")
                var provider = if (rawProvider.isLocal && rawProvider.modelPath.isNullOrBlank()) {
                    rawProvider.copy(
                        modelPath = appSettings.localLlamaModelPath.first()?.takeIf { it.isNotBlank() },
                        localGpuLayers = appSettings.localLlamaGpuLayers.first(),
                    )
                } else if (rawProvider.isLocal) {
                    rawProvider.copy(localGpuLayers = appSettings.localLlamaGpuLayers.first())
                } else {
                    rawProvider
                }
                if (provider.isLocal && provider.modelPath.isNullOrBlank()) {
                    throw IllegalStateException("Import a GGUF model in Settings > Local Models and set it active.")
                }
                if (!provider.isLocal && provider.activeModel == null) {
                    val fetched = streamClient.fetchModels(provider)
                        .distinctBy { it.first }
                        .sortedBy { it.first }
                    if (fetched.isEmpty()) {
                        throw IllegalStateException("No model selected and no models were returned by ${provider.effectiveModelsUrl}")
                    }
                    provider = provider.copy(
                        models = fetched.mapIndexed { index, (id, label) ->
                            ModelConfig(
                                modelId = id,
                                displayName = label?.takeIf { it.isNotBlank() && it != id },
                                isActive = index == 0,
                            )
                        },
                        updatedAt = System.currentTimeMillis(),
                    )
                    providerRep.saveProvider(provider, providerRep.getApiKey(provider.id.value))
                }

                val apiMessages = buildApiMessages(chatId, content, stableAttachments)
                val memories = memoryRepository.search(content, limit = 6).map { memory ->
                    "${memory.kind}: ${memory.content}"
                }
                val systemPrompt = SystemPromptComposer.compose(
                    memories = memories,
                    skills = appSettings.skills.first().filter { it.isEnabled }.map { "- ${it.name}: ${it.description}" },
                    additionalPrompt = appSettings.customInstructions.first(),
                    enabledTools = toolRegistry.getToolsForProvider(provider).map { it.name },
                )
                val fullMessages = listOf(ApiMessage(role = "system", content = systemPrompt)) + apiMessages

                val agentLoop = AgentLoop(
                    client = streamClient,
                    toolRegistry = toolRegistry,
                    localModelManager = localModelManager,
                    androidContext = androidContext,
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

    private suspend fun buildApiMessages(chatId: ChatId, newUserContent: String, newAttachments: List<MessageAttachment>): List<ApiMessage> {
        val existing = messageDao.getForChat(chatId.value).map { it.toDomain() }
        val messages = existing
            .filter { it.role == MessageRole.user || it.role == MessageRole.assistant || it.role == MessageRole.system || it.role == MessageRole.tool }
            .map { msg ->
                when (msg.role) {
                    MessageRole.tool -> ApiMessage(role = "tool", content = msg.content, toolCallId = msg.toolCallId?.value)
                    else -> msg.toApiMessage()
                }
            }.toMutableList()
        if (existing.none { it.content == newUserContent && it.role == MessageRole.user }) {
            messages.add(Message(chatId = chatId, role = MessageRole.user, content = newUserContent, attachments = newAttachments).toApiMessage())
        }
        return messages
    }

    private fun Message.toApiMessage(): ApiMessage {
        if (role != MessageRole.user || attachments.none { it.kind == "image" }) {
            val attachmentText = if (attachments.isEmpty()) "" else attachments.joinToString(
                prefix = "\n\nAttachments:\n",
                separator = "\n",
            ) { "- ${it.name} (${it.mimeType})" }
            return ApiMessage(role = role.wire, content = content + attachmentText)
        }
        val parts = mutableListOf<ApiContentPart>()
        parts.add(ApiContentPart(type = "text", text = content.ifBlank { "Please analyze the attached image." }))
        attachments.filter { it.kind == "image" }.take(4).forEach { attachment ->
            readAttachmentDataUri(attachment)?.let { dataUri ->
                parts.add(ApiContentPart(type = "image_url", imageUrl = dataUri))
            }
        }
        return if (parts.size == 1) ApiMessage(role = role.wire, content = content)
        else ApiMessage(role = role.wire, contentParts = parts)
    }

    private fun readAttachmentDataUri(attachment: MessageAttachment): String? {
        return try {
            val bytes = androidContext.contentResolver.openInputStream(Uri.parse(attachment.uri))?.use { it.readBytes() }
                ?: return null
            "data:${attachment.mimeType};base64,${Base64.encodeToString(bytes, Base64.NO_WRAP)}"
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun persistAttachments(attachments: List<MessageAttachment>): List<MessageAttachment> = withContext(Dispatchers.IO) {
        if (attachments.isEmpty()) return@withContext emptyList()
        val dir = File(androidContext.filesDir, "chat_attachments").apply { mkdirs() }
        attachments.map { attachment ->
            try {
                val uri = Uri.parse(attachment.uri)
                if (uri.scheme == "file" && uri.path?.startsWith(dir.absolutePath) == true) {
                    attachment
                } else {
                    val safeName = attachment.name.replace(Regex("""[^A-Za-z0-9._-]"""), "_").ifBlank { "attachment" }
                    val target = File(dir, "${UUID.randomUUID()}-$safeName")
                    androidContext.contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output -> input.copyTo(output) }
                    } ?: return@map attachment
                    attachment.copy(uri = Uri.fromFile(target).toString(), sizeBytes = target.length())
                }
            } catch (_: Exception) {
                attachment
            }
        }
    }

    private fun firstChatTitle(content: String, attachments: List<MessageAttachment>): String {
        val textTitle = content.trim().replace('\n', ' ').take(50)
        if (textTitle.isNotBlank()) return textTitle
        return attachments.firstOrNull()?.name?.take(50) ?: "Attachment"
    }

    private fun ProviderConfig.displayModelName(): String {
        if (isLocal) {
            val path = modelPath
            return when {
                !path.isNullOrBlank() -> path.substringAfterLast('/')
                activeModel != null -> activeModel?.label.orEmpty()
                else -> "Local GGUF"
            }
        }
        return activeModel?.label ?: activeModel?.modelId ?: name
    }

    private suspend fun loadPromptTemplates() {
        _uiState.update {
            it.copy(promptTemplates = promptTemplateDao.getAll().map { template -> template.toDomain() })
        }
    }
}
