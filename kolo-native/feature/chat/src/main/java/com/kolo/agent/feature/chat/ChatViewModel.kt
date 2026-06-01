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
    val allChats: List<Chat> = emptyList(),
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
    val showTokenUsage: Boolean = true,
    val folders: List<Folder> = emptyList(),
    val activeFolderId: FolderId? = null,
    val chatSearchQuery: String = "",
    val pendingApproval: ToolPermissionApproval? = null,
    val isRefreshingModels: Boolean = false,
    val modelFetchStatus: String? = null,
    val activeProviderReadinessError: String? = null,
    val localBridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown,
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
    private val refreshingProviderModels = mutableSetOf<String>()
    private var localBridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown

    /** Continuation for pending tool approval — resumed by approve/deny actions. */
    private var approvalContinuation: kotlin.coroutines.Continuation<Boolean>? = null

    init {
        viewModelScope.launch {
            localModelManager.checkBridgeAvailability()
            localModelManager.bridgeStatus.collect { status ->
                localBridgeStatus = status
                _uiState.update { it.copy(localBridgeStatus = status) }
            }
        }
        viewModelScope.launch {
            loadFolders()
            loadChatList()
        }
        viewModelScope.launch {
            combine(providerRep.providersFlow, appSettings.localLlamaModelPath) { providers, localModelPath ->
                val activeProvider = providers.firstOrNull { it.isActive }
                val readinessError = evaluateProviderReadinessError(activeProvider, localModelPath)
                _uiState.update {
                    it.copy(
                        activeProvider = activeProvider?.name,
                        activeModel = activeProvider?.displayModelName(),
                        activeProviderConfig = activeProvider,
                        activeProviderReadinessError = readinessError,
                        isRefreshingModels = false,
                        modelFetchStatus = null,
                    )
                }

                activeProvider?.let {
                    if (!it.isLocal && it.models.isEmpty()) {
                        refreshActiveProviderModelsInternal(it, markAsBusy = false)
                    }
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
        viewModelScope.launch {
            appSettings.showTokenUsage.collect { showTokenUsage ->
                _uiState.update { it.copy(showTokenUsage = showTokenUsage) }
            }
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
        val allChats = chatDao.getAll().map { it.toDomain() }
        val chats = allChats
            .filter { folderId == null || it.folderId == folderId }
            .filter { query.isBlank() || it.title.lowercase().contains(query) || it.id.value in matchingChatIds }
        _uiState.update { it.copy(chatList = chats, allChats = allChats) }
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

    fun clearPendingApproval() {
        _uiState.update { it.copy(pendingApproval = null) }
        val continuation = approvalContinuation
        approvalContinuation = null
        continuation?.resume(false)
    }

    private fun evaluateProviderReadinessError(provider: ProviderConfig?, localModelPath: String?): String? {
        if (provider == null) return "No provider configured"
        if (provider.baseUrl.isBlank()) return "Provider endpoint is missing"

        if (provider.isLocal) {
            if (localBridgeStatus == LocalModelManager.BridgeStatus.Unavailable) {
                return "Local llama.cpp runtime is unavailable"
            }
            if (localBridgeStatus == LocalModelManager.BridgeStatus.Checking) {
                return "Checking local runtime availability"
            }
            val effectiveModelPath = provider.modelPath.orEmpty().ifBlank { localModelPath.orEmpty() }
            if (effectiveModelPath.isBlank()) {
                return "Import or select a local GGUF model first."
            }
            val modelFile = File(effectiveModelPath)
            return when {
                !modelFile.exists() -> "Configured local model file does not exist"
                !modelFile.isFile -> "Configured local model path is not a file"
                else -> null
            }
        }

        if (provider.activeModel == null) {
            return "Remote provider has no model selected"
        }
        return null
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
        refreshActiveProviderModelsInternal(provider)
    }

    private fun refreshActiveProviderModelsInternal(
        provider: ProviderConfig,
        markAsBusy: Boolean = true,
    ) {
        if (provider.isLocal) return
        if (!refreshingProviderModels.add(provider.id.value)) return
        viewModelScope.launch {
            if (markAsBusy) {
                _uiState.update {
                    it.copy(
                        isRefreshingModels = true,
                        modelFetchStatus = "Fetching models for ${provider.name}...",
                    )
                }
            }
            try {
                val fetched = streamClient.fetchModels(provider)
                    .distinctBy { it.first }
                    .sortedBy { it.first }

                if (fetched.isEmpty()) {
                    val message = "No models returned by ${provider.effectiveModelsUrl}"
                    _uiState.update {
                        it.copy(
                            error = it.error ?: message,
                            modelFetchStatus = message,
                        )
                    }
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
                _uiState.update {
                    it.copy(
                        modelFetchStatus = "Fetched ${fetched.size} models",
                    )
                }
            } catch (e: Exception) {
                val error = "Model fetch failed: ${e.message ?: "unknown error"}"
                _uiState.update { it.copy(error = error, modelFetchStatus = error) }
            } finally {
                refreshingProviderModels.remove(provider.id.value)
                if (markAsBusy) {
                    _uiState.update {
                        it.copy(isRefreshingModels = false)
                    }
                }
            }
        }
    }

    fun touchPromptTemplate(templateId: TemplateId) {
        viewModelScope.launch {
            promptTemplateDao.touch(templateId.value)
            loadPromptTemplates()
        }
    }

    fun sendMessage(
        content: String,
        attachments: List<MessageAttachment> = emptyList(),
        onAccepted: (Boolean, String, List<MessageAttachment>) -> Unit = { _, _, _ -> },
    ) {
        if (content.isBlank() && attachments.isEmpty()) {
            onAccepted(false, content, attachments)
            return
        }
        if (_uiState.value.isStreaming) return
        val readinessError = _uiState.value.activeProviderReadinessError
        if (readinessError != null) {
            _uiState.update { it.copy(error = readinessError) }
            onAccepted(false, content, attachments)
            return
        }
        val chatId = currentChatId ?: run {
            val newId = newChat()
            currentChatId = newId
            newId
        }

        viewModelScope.launch {
            isCancelled = false
            val persisted = persistAttachments(attachments)
            if (persisted.failed.isNotEmpty()) {
                _uiState.update {
                    it.copy(
                        error = "Unable to attach: ${persisted.failed.take(2).joinToString(", ")}" +
                            if (persisted.failed.size > 2) " and ${persisted.failed.size - 2} more" else "",
                    )
                }
                onAccepted(false, content, attachments)
                return@launch
            }

            val stableAttachments = persisted.attachments
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
                    val refreshed = ensureRemoteProviderHasModels(provider)
                    if (refreshed == null) {
                        throw IllegalStateException("No model selected and no models were returned by ${provider.effectiveModelsUrl}")
                    }
                    provider = refreshed
                }
                val providerReadyError = evaluateProviderReadinessError(
                    provider,
                    if (provider.isLocal) appSettings.localLlamaModelPath.first() else null,
                )
                if (providerReadyError != null) {
                    throw IllegalStateException(providerReadyError)
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

                onAccepted(true, "", emptyList())

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
                onAccepted(false, content, attachments)
                _uiState.update { it.copy(error = e.message, isStreaming = false, isLoading = false) }
            }
        }
    }

    private suspend fun ensureRemoteProviderHasModels(provider: ProviderConfig): ProviderConfig? {
        if (provider.isLocal) return provider
        val fetched = streamClient.fetchModels(provider)
            .distinctBy { it.first }
            .sortedBy { it.first }

        if (fetched.isEmpty()) return null

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
        return updated
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

    private data class PersistedAttachments(
        val attachments: List<MessageAttachment>,
        val failed: List<String>,
    )

    private suspend fun persistAttachments(attachments: List<MessageAttachment>): PersistedAttachments = withContext(Dispatchers.IO) {
        if (attachments.isEmpty()) return@withContext PersistedAttachments(emptyList(), emptyList())
        val dir = File(androidContext.filesDir, "chat_attachments").apply { mkdirs() }
        val failed = mutableListOf<String>()
        val processed = attachments.mapNotNull { attachment ->
            try {
                val uri = Uri.parse(attachment.uri)
                if (uri.scheme == "file" && uri.path?.startsWith(dir.absolutePath) == true) {
                    attachment
                } else {
                    val safeName = attachment.name.replace(Regex("""[^A-Za-z0-9._-]"""), "_").ifBlank { "attachment" }
                    val target = File(dir, "${UUID.randomUUID()}-$safeName")
                    androidContext.contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output -> input.copyTo(output) }
                    } ?: run {
                        failed.add(attachment.name)
                        return@mapNotNull null
                    }
                    attachment.copy(uri = Uri.fromFile(target).toString(), sizeBytes = target.length())
                }
            } catch (_: Exception) {
                failed.add(attachment.name)
                null
            }
        }
        PersistedAttachments(processed, failed)
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
