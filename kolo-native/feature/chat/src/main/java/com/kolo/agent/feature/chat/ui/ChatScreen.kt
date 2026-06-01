package com.kolo.agent.feature.chat.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kolo.agent.core.model.*
import com.kolo.agent.feature.chat.ChatUiState
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import kotlin.math.min

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    state: ChatUiState,
    onSendMessage: (String, List<MessageAttachment>, (Boolean) -> Unit) -> Unit,
    onCancel: () -> Unit,
    onClearError: () -> Unit = {},
    onSelectChat: (ChatId) -> Unit = {},
    onNewChat: () -> Unit = {},
    onDeleteChat: (ChatId) -> Unit = {},
    onSetChatSearchQuery: (String) -> Unit = {},
    onSetActiveFolder: (FolderId?) -> Unit = {},
    onCreateFolder: (String) -> Unit = {},
    onDeleteFolder: (FolderId) -> Unit = {},
    onMoveChat: (ChatId, FolderId?) -> Unit = { _, _ -> },
    onSetPinned: (ChatId, Boolean) -> Unit = { _, _ -> },
    onNavigateSettings: () -> Unit = {},
    onSetActiveModel: (String) -> Unit = {},
    onRefreshActiveModels: () -> Unit = {},
    onUsePromptTemplate: (TemplateId) -> Unit = {},
    onAllowOnce: (ToolPermissionApproval) -> Unit = {},
    onAlwaysAllow: (ToolPermissionApproval) -> Unit = {},
    onDenyOnce: (ToolPermissionApproval) -> Unit = {},
    onBlock: (ToolPermissionApproval) -> Unit = {},
) {
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()

    ModalNavigationDrawer(
        drawerState = drawerState,
                drawerContent = {
            ChatDrawer(
                chats = state.chatList,
                folders = state.folders,
                activeFolderId = state.activeFolderId,
                searchQuery = state.chatSearchQuery,
                currentChatId = state.currentChatId,
                activeProviderConfig = state.activeProviderConfig,
                isLocked = state.isStreaming || state.isLoading,
                onSelectChat = { chatId ->
                    onSelectChat(chatId)
                    scope.launch { drawerState.close() }
                },
                onNewChat = {
                    onNewChat()
                    scope.launch { drawerState.close() }
                },
                onDeleteChat = onDeleteChat,
                onSetSearchQuery = onSetChatSearchQuery,
                onSetActiveFolder = onSetActiveFolder,
                allChats = state.allChats,
                onCreateFolder = onCreateFolder,
                onDeleteFolder = onDeleteFolder,
                onMoveChat = onMoveChat,
                onSetPinned = onSetPinned,
                onNavigateSettings = onNavigateSettings,
                drawerState = drawerState,
            )
        },
    ) {
        ChatContent(
            state = state,
            onSendMessage = onSendMessage,
            onCancel = onCancel,
            onClearError = onClearError,
            onOpenDrawer = { scope.launch { drawerState.open() } },
            onNavigateSettings = onNavigateSettings,
            onSetActiveModel = onSetActiveModel,
            onRefreshActiveModels = onRefreshActiveModels,
            onUsePromptTemplate = onUsePromptTemplate,
            onAllowOnce = onAllowOnce,
            onAlwaysAllow = onAlwaysAllow,
            onDenyOnce = onDenyOnce,
            onBlock = onBlock,
        )
    }
}

@Composable
private fun ChatDrawer(
    chats: List<Chat>,
    allChats: List<Chat>,
    folders: List<Folder>,
    activeProviderConfig: ProviderConfig?,
    activeFolderId: FolderId?,
    searchQuery: String,
    currentChatId: ChatId?,
    isLocked: Boolean,
    onSelectChat: (ChatId) -> Unit,
    onNewChat: () -> Unit,
    onDeleteChat: (ChatId) -> Unit,
    onSetSearchQuery: (String) -> Unit,
    onSetActiveFolder: (FolderId?) -> Unit,
    onCreateFolder: (String) -> Unit,
    onDeleteFolder: (FolderId) -> Unit,
    onMoveChat: (ChatId, FolderId?) -> Unit,
    onSetPinned: (ChatId, Boolean) -> Unit,
    onNavigateSettings: () -> Unit,
    drawerState: DrawerState,
) {
    var showFolderDialog by remember { mutableStateOf(false) }
    var folderDraft by remember { mutableStateOf("") }
    var folderDraftError by remember { mutableStateOf<String?>(null) }
    var pendingDeleteChat by remember { mutableStateOf<ChatId?>(null) }
    var pendingMoveToNoFolderChatId by remember { mutableStateOf<ChatId?>(null) }
    var pendingDeleteFolder by remember { mutableStateOf<Folder?>(null) }
    var openMenuChatId by remember { mutableStateOf<ChatId?>(null) }
    val providerStatusText = when {
        activeProviderConfig == null -> "No provider configured"
        activeProviderConfig.isLocal && activeProviderConfig.activeModel == null -> "Local provider missing active model"
        !activeProviderConfig.isLocal && activeProviderConfig.activeModel == null -> "Remote provider has no model selected"
        else -> null
    }
    ModalDrawerSheet(
        modifier = Modifier.width(280.dp),
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Kolo AI", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        HorizontalDivider()

        if (providerStatusText != null) {
            Text(
                text = providerStatusText,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 4.dp),
            )
        }

        // New chat button
        FilledTonalButton(
            onClick = onNewChat,
            enabled = !isLocked,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("New Chat", style = MaterialTheme.typography.bodyMedium)
        }

        OutlinedTextField(
            value = searchQuery,
            onValueChange = onSetSearchQuery,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
            placeholder = { Text("Search chats") },
            singleLine = true,
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(18.dp)) },
            trailingIcon = {
                if (searchQuery.isNotBlank()) {
                    IconButton(onClick = { onSetSearchQuery("") }, modifier = Modifier.size(20.dp)) {
                        Icon(Icons.Filled.Close, contentDescription = "Clear search", modifier = Modifier.size(14.dp))
                    }
                }
            },
            textStyle = MaterialTheme.typography.bodySmall,
        )

        LazyColumn(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
        ) {
            item {
                NavigationDrawerItem(
                    label = { Text("All chats", style = MaterialTheme.typography.bodySmall) },
                    icon = { Icon(Icons.Filled.Forum, contentDescription = null, modifier = Modifier.size(16.dp)) },
                    selected = activeFolderId == null,
                    onClick = { onSetActiveFolder(null) },
                    badge = { Text(allChats.size.toString(), style = MaterialTheme.typography.labelSmall) },
                    modifier = Modifier.padding(vertical = 1.dp),
                )
            }
            items(folders, key = { it.id.value }) { folder ->
                val folderChatCount = allChats.count { it.folderId == folder.id }
                NavigationDrawerItem(
                    label = { Text(folder.name, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    icon = { Icon(Icons.Filled.Folder, contentDescription = null, modifier = Modifier.size(16.dp)) },
                    selected = activeFolderId == folder.id,
                    onClick = { onSetActiveFolder(folder.id) },
                    badge = {
                        Row {
                            if (folderChatCount > 0) {
                                Text(folderChatCount.toString(), style = MaterialTheme.typography.labelSmall)
                            }
                            Spacer(modifier = Modifier.width(2.dp))
                            FilledTonalButton(
                                onClick = { pendingDeleteFolder = folder },
                                contentPadding = PaddingValues(horizontal = 6.dp, vertical = 2.dp),
                                modifier = Modifier.height(22.dp),
                            ) {
                                Icon(Icons.Filled.Delete, contentDescription = "Delete folder", modifier = Modifier.size(12.dp))
                                Spacer(modifier = Modifier.width(2.dp))
                                Text("Delete", style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    },
                    modifier = Modifier.padding(vertical = 1.dp),
                )
            }
        }
        TextButton(
            onClick = { showFolderDialog = true },
            modifier = Modifier.padding(horizontal = 8.dp),
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
        ) {
            Icon(Icons.Filled.CreateNewFolder, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(4.dp))
            Text("New Folder", style = MaterialTheme.typography.labelMedium)
        }

        // Chat list
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(vertical = 4.dp),
        ) {
            items(chats, key = { it.id.value }) { chat ->
                val isCurrent = chat.id == currentChatId
                NavigationDrawerItem(
                    label = {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = chat.title,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                "${chat.messageCount} messages",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                    icon = {
                        Icon(
                            if (chat.isPinned) Icons.Filled.PushPin else Icons.Filled.ChatBubbleOutline,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = if (isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    badge = {
                        Row {
                            FilledTonalButton(
                                onClick = { openMenuChatId = chat.id },
                                contentPadding = PaddingValues(horizontal = 6.dp, vertical = 2.dp),
                                modifier = Modifier.height(22.dp),
                            ) {
                                Icon(Icons.Filled.MoreVert, contentDescription = null, modifier = Modifier.size(12.dp))
                                Spacer(modifier = Modifier.width(3.dp))
                                Text("Actions", style = MaterialTheme.typography.labelSmall)
                            }
                            DropdownMenu(expanded = openMenuChatId == chat.id, onDismissRequest = { openMenuChatId = null }) {
                                DropdownMenuItem(
                                    text = { Text(if (chat.isPinned) "Unpin" else "Pin") },
                                    leadingIcon = { Icon(Icons.Filled.PushPin, contentDescription = null) },
                                    onClick = {
                                        openMenuChatId = null
                                        onSetPinned(chat.id, !chat.isPinned)
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text("No folder") },
                                    leadingIcon = { Icon(Icons.Filled.FolderOff, contentDescription = null) },
                                    onClick = {
                                        openMenuChatId = null
                                        pendingMoveToNoFolderChatId = chat.id
                                    },
                                )
                                folders.forEach { folder ->
                                    DropdownMenuItem(
                                        text = { Text(folder.name) },
                                        leadingIcon = { Icon(Icons.Filled.Folder, contentDescription = null) },
                                        onClick = {
                                            openMenuChatId = null
                                            onMoveChat(chat.id, folder.id)
                                        },
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text("Delete") },
                                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
                                    onClick = {
                                        openMenuChatId = null
                                        pendingDeleteChat = chat.id
                                    },
                                )
                            }
                        }
                    },
                    selected = isCurrent,
                    onClick = { onSelectChat(chat.id) },
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 1.dp),
                )
            }
        }

        HorizontalDivider()

        // Settings button at bottom
        NavigationDrawerItem(
            label = { Text("Settings") },
            icon = { Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(18.dp)) },
            selected = false,
            onClick = onNavigateSettings,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp).navigationBarsPadding(),
        )
    }

    if (showFolderDialog) {
        AlertDialog(
            onDismissRequest = { showFolderDialog = false },
            title = { Text("New Folder") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedTextField(
                        value = folderDraft,
                        onValueChange = {
                            folderDraft = it
                            folderDraftError = when {
                                it.isBlank() -> "Folder name is required"
                                it.trim().length > 40 -> "Name is too long"
                                folders.any { folder -> folder.name.equals(it.trim(), ignoreCase = true) } -> "A folder with this name already exists"
                                else -> null
                            }
                        },
                        label = { Text("Folder name") },
                        isError = folderDraftError != null,
                        singleLine = true,
                    )
                    folderDraftError?.let {
                        Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onCreateFolder(folderDraft)
                        folderDraft = ""
                        folderDraftError = null
                        showFolderDialog = false
                    },
                    enabled = folderDraftError == null && folderDraft.isNotBlank(),
                ) { Text("Create") }
            },
            dismissButton = { TextButton(onClick = { showFolderDialog = false }) { Text("Cancel") } },
        )
    }

    pendingDeleteChat?.let { chatId ->
        AlertDialog(
            onDismissRequest = { pendingDeleteChat = null },
            title = { Text("Delete chat?") },
            text = { Text("Delete this chat and all its messages? This cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDeleteChat(chatId)
                        pendingDeleteChat = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { pendingDeleteChat = null }) { Text("Cancel") } },
        )
    }

    pendingDeleteFolder?.let { folder ->
        val affectedChats = allChats.count { it.folderId == folder.id }
        AlertDialog(
            onDismissRequest = { pendingDeleteFolder = null },
            title = { Text("Delete folder?") },
            text = {
                val suffix = if (affectedChats > 0) " and move $affectedChats chat${if (affectedChats != 1) "s" else ""} out" else ""
                Text("Delete \"${folder.name}\"$suffix? This cannot be undone.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDeleteFolder(folder.id)
                        pendingDeleteFolder = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { pendingDeleteFolder = null }) { Text("Cancel") } },
        )
    }

    pendingMoveToNoFolderChatId?.let { chatId ->
        val chat = allChats.firstOrNull { it.id == chatId }
        AlertDialog(
            onDismissRequest = { pendingMoveToNoFolderChatId = null },
            title = { Text("Move chat out of folder?") },
            text = {
                Text("Move \"${chat?.title ?: "this chat"}\" to the main list?")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onMoveChat(chatId, null)
                        onSetActiveFolder(null)
                        pendingMoveToNoFolderChatId = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary),
                ) { Text("Move") }
            },
            dismissButton = { TextButton(onClick = { pendingMoveToNoFolderChatId = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun ChatContent(
    state: ChatUiState,
    onSendMessage: (String, List<MessageAttachment>, (Boolean) -> Unit) -> Unit,
    onCancel: () -> Unit,
    onClearError: () -> Unit,
    onOpenDrawer: () -> Unit,
    onNavigateSettings: () -> Unit,
    onSetActiveModel: (String) -> Unit,
    onRefreshActiveModels: () -> Unit,
    onUsePromptTemplate: (TemplateId) -> Unit,
    onAllowOnce: (ToolPermissionApproval) -> Unit,
    onAlwaysAllow: (ToolPermissionApproval) -> Unit,
    onDenyOnce: (ToolPermissionApproval) -> Unit,
    onBlock: (ToolPermissionApproval) -> Unit,
) {
    val context = LocalContext.current
    var inputText by remember { mutableStateOf("") }
    var pendingAttachments by remember { mutableStateOf<List<MessageAttachment>>(emptyList()) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val timelineItemCount by remember(state) {
        derivedStateOf {
            var count = state.messages.size
            if (state.isStreaming && state.streamingContent.isNotEmpty()) count += 1
            if (state.isStreaming && state.streamingThinking.isNotEmpty()) count += 1
            if (state.activeToolCalls.isNotEmpty()) count += 1
            if (state.isLoading && !state.isStreaming) count += 1
            if (state.messages.isEmpty() && !state.isLoading) count += 1
            count
        }
    }
    val showScrollToBottom by remember {
        derivedStateOf {
            listState.firstVisibleItemIndex > 1
        }
    }

    LaunchedEffect(
        state.messages.size,
        state.streamingContent,
        state.streamingThinking,
        state.activeToolCalls.size,
        state.toolResults.size,
        state.isLoading,
        state.isStreaming,
    ) {
        val targetIndex = (timelineItemCount - 1).coerceAtLeast(0)
        if (timelineItemCount > 0 && !state.isStreaming) {
            listState.animateScrollToItem(targetIndex)
        }
    }

    Scaffold(
        topBar = {
            ChatHeader(
                provider = state.activeProvider,
                model = state.activeModel,
                providerConfig = state.activeProviderConfig,
                onOpenDrawer = onOpenDrawer,
                onSettings = onNavigateSettings,
                onSetActiveModel = onSetActiveModel,
                onRefreshActiveModels = onRefreshActiveModels,
                isRefreshingModels = state.isRefreshingModels,
                modelFetchStatus = state.modelFetchStatus,
            )
        },
        bottomBar = {
            ChatInputBar(
                value = inputText,
                onValueChange = { inputText = it },
                attachments = pendingAttachments,
                onAttachmentsChanged = { pendingAttachments = it },
                onSend = {
                    if (inputText.isNotBlank() || pendingAttachments.isNotEmpty()) {
                        onSendMessage(inputText.trim(), pendingAttachments) { accepted ->
                            if (accepted) {
                                inputText = ""
                                pendingAttachments = emptyList()
                            }
                        }
                    }
                },
                isStreaming = state.isStreaming,
                sendDisabledReason = state.activeProviderReadinessError,
                onCancel = onCancel,
                promptTemplates = state.promptTemplates,
                    onInsertPrompt = { template ->
                        Toast.makeText(context, "Template \"${template.name}\" inserted", Toast.LENGTH_SHORT).show()
                        inputText = if (inputText.isBlank()) template.body else "${inputText.trimEnd()}\n\n${template.body}"
                        onUsePromptTemplate(template.id)
                    },
                )
            },
            floatingActionButton = {
                if (showScrollToBottom && state.messages.isNotEmpty()) {
                    FloatingActionButton(
                        onClick = {
                            val last = (timelineItemCount - 1).coerceAtLeast(0)
                            scope.launch { listState.animateScrollToItem(last) }
                        },
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ) {
                        Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Scroll to latest message")
                    }
                }
            },
            contentWindowInsets = WindowInsets(0),
        ) { paddingValues ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
        ) {
            // Error banner
            state.error?.let { errorStr ->
                ErrorBanner(error = errorStr, onDismiss = onClearError)
            }

            // Tool approval banner
            state.pendingApproval?.let { approval ->
                ToolApprovalBanner(
                    approval = approval,
                    onAllowOnce = { onAllowOnce(approval) },
                    onAlwaysAllow = { onAlwaysAllow(approval) },
                    onDenyOnce = { onDenyOnce(approval) },
                    onBlock = { onBlock(approval) },
                )
            }

            // Messages list
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
                contentPadding = PaddingValues(vertical = 6.dp),
            ) {
                itemsIndexed(state.messages) { index, message ->
                    val previous = state.messages.getOrNull(index - 1)
                    val shouldShowDateHeader = previous == null || !isSameCalendarDay(previous.createdAt, message.createdAt)
                    val shouldStartNewGroup = previous?.role != message.role
                    if (shouldShowDateHeader) {
                        MessageDateSeparator(timestamp = message.createdAt)
                        Spacer(Modifier.height(2.dp))
                    }
                    MessageBubble(message = message, isGroupedWithPrevious = !shouldStartNewGroup)
                }

                if (state.isStreaming && state.streamingContent.isNotEmpty()) {
                    item { StreamingBubble(content = state.streamingContent) }
                }

                if (state.isStreaming && state.streamingThinking.isNotEmpty()) {
                    item { ThinkingBubble(content = state.streamingThinking) }
                }

                if (state.activeToolCalls.isNotEmpty()) {
                    item {
                        ToolCallsPanel(
                            calls = state.activeToolCalls,
                            results = state.toolResults,
                        )
                    }
                }

                if (state.isLoading && !state.isStreaming) {
                    item { LoadingIndicator() }
                }

                if (state.messages.isEmpty() && !state.isLoading) {
                    item { EmptyChatState(hasProvider = state.activeProviderConfig != null, onNavigateSettings = onNavigateSettings) }
                }
            }

            // Token usage
            if (state.showTokenUsage) {
                state.tokenUsage?.let { usage ->
                    TokenUsageBar(usage = usage)
                }
            }
        }
    }
}

// ──── Chat header with drawer toggle ────

@Composable
private fun ChatHeader(
    provider: String?,
    model: String?,
    providerConfig: ProviderConfig?,
    onOpenDrawer: () -> Unit,
    onSettings: () -> Unit,
    onSetActiveModel: (String) -> Unit,
    onRefreshActiveModels: () -> Unit,
    isRefreshingModels: Boolean,
    modelFetchStatus: String?,
) {
    var expanded by remember { mutableStateOf(false) }
    var modelSearch by remember(providerConfig?.id) { mutableStateOf("") }
    val models = providerConfig?.models.orEmpty()
    val filteredModels = remember(modelSearch, models) {
        if (modelSearch.isBlank()) models
        else models.filter { it.label.contains(modelSearch, ignoreCase = true) || it.modelId.contains(modelSearch, ignoreCase = true) }
    }
    val hasProvider = providerConfig != null
    val isLocalProvider = providerConfig?.isLocal == true
    val activeModelId = providerConfig?.activeModel?.modelId
    val activeModelDisplay = providerConfig?.activeModel?.label
        ?.ifBlank { providerConfig.activeModel?.modelId }
        ?: if (isLocalProvider) {
            providerConfig?.modelPath?.substringAfterLast("/") ?: "Local GGUF"
        } else {
            model ?: "No model selected"
        }
    val runtimeLabel = if (providerConfig?.isLocal == true) {
        if (providerConfig.localGpuLayers > 0) "GPU (${providerConfig.localGpuLayers})" else "CPU"
    } else {
        "Remote"
    }

    Surface(
        tonalElevation = 2.dp,
        shadowElevation = 1.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 2.dp, end = 2.dp, top = 0.dp, bottom = 0.dp)
                .statusBarsPadding(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onOpenDrawer, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Filled.Menu, contentDescription = "Chat list", modifier = Modifier.size(22.dp))
            }
            Spacer(modifier = Modifier.width(4.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = model ?: "Kolo AI",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    lineHeight = 18.sp,
                )
                if (provider != null) {
                    Text(
                        text = "$provider • $activeModelDisplay",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        lineHeight = 14.sp,
                    )
                } else {
                    Text(
                        text = "No provider configured",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                        lineHeight = 14.sp,
                    )
                }
                modelFetchStatus?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            if (providerConfig?.isLocal == true) {
                AssistChip(
                    onClick = onSettings,
                    label = { Text(runtimeLabel, style = MaterialTheme.typography.labelSmall) },
                    leadingIcon = {
                        Icon(Icons.Filled.Speed, contentDescription = null, modifier = Modifier.size(12.dp))
                    },
                )
            }

            if (hasProvider) {
                BadgedBox(
                    modifier = Modifier.padding(start = 2.dp),
                    badge = {
                        if (isRefreshingModels) {
                            Badge { Icon(Icons.Filled.CloudSync, contentDescription = "Syncing", modifier = Modifier.size(10.dp)) }
                        }
                    }
                    ) {
                    OutlinedButton(
                        onClick = { expanded = true },
                        contentPadding = PaddingValues(horizontal = 10.dp),
                    ) {
                        Text(activeModelDisplay, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.width(2.dp))
                        Icon(Icons.Filled.ArrowDropDown, contentDescription = "Model picker", modifier = Modifier.size(16.dp))
                    }
                }
                Box {
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        if (isRefreshingModels) {
                            DropdownMenuItem(
                                enabled = false,
                                leadingIcon = { CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp) },
                                text = { Text("Refreshing models…") },
                                onClick = {},
                            )
                            HorizontalDivider()
                        }

                        if (models.isEmpty()) {
                            DropdownMenuItem(
                                text = { Text(if (isLocalProvider) "No local model loaded" else "No models loaded") },
                                leadingIcon = {
                                    Icon(
                                        if (isLocalProvider) Icons.Filled.Memory else Icons.Filled.Cloud,
                                        contentDescription = null,
                                        modifier = Modifier.size(18.dp),
                                    )
                                },
                                enabled = false,
                                onClick = {},
                            )
                        } else {
                            if (models.size > 6) {
                                OutlinedTextField(
                                    modifier = Modifier
                                        .padding(horizontal = 8.dp)
                                        .width(220.dp),
                                    value = modelSearch,
                                    onValueChange = { modelSearch = it },
                                    singleLine = true,
                                    placeholder = { Text("Search models") },
                                    textStyle = MaterialTheme.typography.bodySmall,
                                    trailingIcon = {
                                        if (modelSearch.isNotBlank()) {
                                            IconButton(onClick = { modelSearch = "" }, modifier = Modifier.size(16.dp)) {
                                                Icon(Icons.Filled.Close, contentDescription = "Clear", modifier = Modifier.size(12.dp))
                                            }
                                        }
                                    },
                                )
                                HorizontalDivider()
                            }

                            if (filteredModels.isEmpty()) {
                                DropdownMenuItem(text = { Text("No models match") }, onClick = {}, enabled = false)
                            } else {
                                filteredModels.forEach { option ->
                                    DropdownMenuItem(
                                        text = { Text(option.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                        leadingIcon = {
                                            if (option.modelId == activeModelId) {
                                                Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                                            } else {
                                                Spacer(modifier = Modifier.size(18.dp))
                                            }
                                        },
                                        onClick = {
                                            expanded = false
                                            onSetActiveModel(option.modelId)
                                        },
                                    )
                                }
                            }
                        }

                        HorizontalDivider()
                        if (!isLocalProvider) {
                            DropdownMenuItem(
                                text = { Text(if (models.isEmpty()) "Fetch models" else "Refresh models") },
                                leadingIcon = { Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp)) },
                                onClick = {
                                    expanded = false
                                    onRefreshActiveModels()
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(if (isLocalProvider) "Local model settings" else "Provider settings") },
                            leadingIcon = { Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(18.dp)) },
                            onClick = {
                                expanded = false
                                onSettings()
                            },
                        )
                    }
                }
            } else {
                FilledTonalButton(
                    onClick = onSettings,
                    contentPadding = PaddingValues(horizontal = 8.dp),
                ) {
                    Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(14.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Setup", style = MaterialTheme.typography.labelSmall)
                }
            }
            IconButton(onClick = onSettings, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Filled.Settings, contentDescription = "Settings", modifier = Modifier.size(22.dp))
            }
        }
    }
}

// ──── Tool approval banner ────

@Composable
private fun ToolApprovalBanner(
    approval: ToolPermissionApproval,
    onAllowOnce: () -> Unit,
    onAlwaysAllow: () -> Unit,
    onDenyOnce: () -> Unit,
    onBlock: () -> Unit,
) {
    Surface(
        color = when (approval.permission) {
            ToolPermission.dangerous -> MaterialTheme.colorScheme.errorContainer
            ToolPermission.sensitive -> MaterialTheme.colorScheme.tertiaryContainer
            ToolPermission.safe -> MaterialTheme.colorScheme.primaryContainer
        },
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 2.dp),
    ) {
        Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = when (approval.permission) {
                        ToolPermission.dangerous -> Icons.Filled.Warning
                        ToolPermission.sensitive -> Icons.Filled.Shield
                        ToolPermission.safe -> Icons.Filled.CheckCircle
                    },
                    contentDescription = null,
                    tint = when (approval.permission) {
                        ToolPermission.dangerous -> MaterialTheme.colorScheme.error
                        ToolPermission.sensitive -> MaterialTheme.colorScheme.tertiary
                        ToolPermission.safe -> MaterialTheme.colorScheme.primary
                    },
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = approval.toolName.replace("_", " ").replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(modifier = Modifier.weight(1f))
                if (approval.permission == ToolPermission.dangerous) {
                    Badge(contentColor = MaterialTheme.colorScheme.onErrorContainer) { Text("!", style = MaterialTheme.typography.labelSmall) }
                }
            }

            if (approval.arguments.isNotBlank()) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = approval.arguments.take(120) + if (approval.arguments.length > 120) "…" else "",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            Spacer(modifier = Modifier.height(6.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                FilledTonalButton(
                    onClick = onAllowOnce,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ),
                ) { Text("Allow Once", style = MaterialTheme.typography.labelSmall) }

                if (approval.permission != ToolPermission.safe) {
                    OutlinedButton(
                        onClick = onAlwaysAllow,
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
                    ) { Text("Always Allow", style = MaterialTheme.typography.labelSmall) }
                }

                OutlinedButton(
                    onClick = onDenyOnce,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Deny", style = MaterialTheme.typography.labelSmall) }

                if (approval.permission == ToolPermission.dangerous || approval.permission == ToolPermission.sensitive) {
                    TextButton(
                        onClick = onBlock,
                        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 2.dp),
                    ) { Text("Block", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelSmall) }
                }
            }
        }
    }
}

// ──── Message bubble ────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    message: Message,
    isGroupedWithPrevious: Boolean = false,
) {
    val isUser = message.role == MessageRole.user
    val maxWidthFraction = 0.88f
    val configuration = LocalConfiguration.current
    val maxWidthDp = (configuration.screenWidthDp * maxWidthFraction).dp
    val context = LocalContext.current
    val timeText = remember(message.createdAt) {
        DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(message.createdAt))
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Surface(
            shape = if (isGroupedWithPrevious) {
                if (isUser) {
                    RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp, bottomStart = 14.dp, bottomEnd = 2.dp)
                } else {
                    RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp, bottomStart = 2.dp, bottomEnd = 14.dp)
                }
            } else {
                RoundedCornerShape(
                    topStart = 14.dp,
                    topEnd = 14.dp,
                    bottomStart = if (isUser) 14.dp else 2.dp,
                    bottomEnd = if (isUser) 2.dp else 14.dp,
                )
            },
            color = if (isUser) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
            tonalElevation = if (!isUser) 0.5.dp else 0.dp,
            modifier = Modifier
                .widthIn(max = maxWidthDp)
                .combinedClickable(
                    onClick = {},
                    onLongClick = { copyMessageToClipboard(context, message.content) },
                ),
        ) {
            Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)) {
                if (message.role == MessageRole.tool) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(bottom = 2.dp),
                    ) {
                        Icon(
                            imageVector = if (message.toolSuccess == true) Icons.Filled.CheckCircle else Icons.Filled.Error,
                            contentDescription = null,
                            tint = if (message.toolSuccess == true) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(12.dp),
                        )
                        Spacer(modifier = Modifier.width(3.dp))
                        Text(
                            text = message.toolName ?: "Tool",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
                Text(
                    text = message.content,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (isUser) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (message.attachments.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            "Attachments (${message.attachments.size})",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(modifier = Modifier.weight(1f))
                        IconButton(onClick = { copyMessageToClipboard(context, message.content) }, modifier = Modifier.size(18.dp)) {
                            Icon(Icons.Filled.ContentCopy, contentDescription = "Copy message", modifier = Modifier.size(12.dp))
                        }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        message.attachments.forEach { attachment ->
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(
                                        if (isUser) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.14f)
                                        else MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)
                                    )
                                    .clickable { openMessageAttachment(context, attachment) }
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                            ) {
                                Icon(
                                    if (attachment.kind == "image") Icons.Filled.Image else Icons.Filled.AttachFile,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = if (isUser) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Spacer(Modifier.width(4.dp))
                                Text(
                                    attachment.name,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (isUser) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f),
                                )
                                IconButton(onClick = { openMessageAttachment(context, attachment) }, modifier = Modifier.size(18.dp)) {
                                    Icon(Icons.Filled.OpenInNew, contentDescription = "Open", modifier = Modifier.size(12.dp))
                                }
                                IconButton(onClick = { copyTextToClipboard(context, attachment.name) }, modifier = Modifier.size(18.dp)) {
                                    Icon(Icons.Filled.ContentCopy, contentDescription = "Copy filename", modifier = Modifier.size(12.dp))
                                }
                            }
                        }
                    }
                }
                val messageError = message.error
                if (messageError != null) {
                    Text(
                        text = messageError,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                Spacer(modifier = Modifier.height(3.dp))
                Text(
                    text = timeText,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isUser) {
                        MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.72f)
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f)
                    },
                    modifier = Modifier.align(Alignment.End),
                )
            }
        }
    }
}

private fun copyMessageToClipboard(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("Kolo message", text))
    Toast.makeText(context, "Message copied", Toast.LENGTH_SHORT).show()
}

private fun copyTextToClipboard(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("Kolo attachment", text))
    Toast.makeText(context, "Attachment copied", Toast.LENGTH_SHORT).show()
}

private fun openMessageAttachment(context: Context, attachment: MessageAttachment) {
    val uri = Uri.parse(attachment.uri)
    val openIntent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, attachment.mimeType)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    try {
        context.startActivity(Intent.createChooser(openIntent, "Open attachment"))
    } catch (_: ActivityNotFoundException) {
        Toast.makeText(context, "No app available to open ${attachment.name}", Toast.LENGTH_SHORT).show()
    } catch (_: Exception) {
        Toast.makeText(context, "Unable to open ${attachment.name}", Toast.LENGTH_SHORT).show()
    }
}

private fun Context.toMessageAttachment(uri: Uri): MessageAttachment {
    var name = uri.lastPathSegment?.substringAfterLast('/').orEmpty()
    var size = -1L
    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (nameIndex >= 0) name = cursor.getString(nameIndex).orEmpty()
            if (sizeIndex >= 0) size = cursor.getLong(sizeIndex)
        }
    }
    val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
    return MessageAttachment(
        name = name.ifBlank { "attachment" },
        mimeType = mimeType,
        uri = uri.toString(),
        kind = if (mimeType.lowercase().startsWith("image/")) "image" else "file",
        sizeBytes = size,
    )
}

@Composable
private fun StreamingBubble(content: String) {
    val maxWidthFraction = 0.88f
    val configuration = LocalConfiguration.current
    val maxWidthDp = (configuration.screenWidthDp * maxWidthFraction).dp

    Surface(
        shape = RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp, bottomStart = 2.dp, bottomEnd = 14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.widthIn(max = maxWidthDp),
    ) {
        Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)) {
            Text(
                text = content,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val infiniteTransition = rememberInfiniteTransition(label = "cursor")
            val alpha by infiniteTransition.animateFloat(
                initialValue = 0f, targetValue = 1f,
                animationSpec = infiniteRepeatable(animation = tween(500), repeatMode = RepeatMode.Reverse),
                label = "cursor-alpha",
            )
            Text(
                text = "▌",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = alpha),
            )
        }
    }
}

@Composable
private fun ThinkingBubble(content: String) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.tertiaryContainer,
        modifier = Modifier.widthIn(max = (LocalConfiguration.current.screenWidthDp * 0.85f).dp),
    ) {
        Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Psychology, contentDescription = "Thinking", modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.tertiary)
                Spacer(modifier = Modifier.width(3.dp))
                Text("Thinking", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.tertiary, fontWeight = FontWeight.Medium)
            }
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = content.take(300),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
        }
    }
}

@Composable
private fun ToolCallsPanel(
    calls: List<ResolvedToolCall>,
    results: Map<String, ToolExecutionResult>,
) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
        modifier = Modifier.widthIn(max = (LocalConfiguration.current.screenWidthDp * 0.88f).dp),
    ) {
        Column(modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Build, contentDescription = "Tools", modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.secondary)
                Spacer(modifier = Modifier.width(4.dp))
                Text("${calls.size} tool call${if (calls.size != 1) "s" else ""}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.secondary, fontWeight = FontWeight.Medium)
            }
            calls.forEach { call ->
                val result = results[call.id]
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 1.dp)) {
                    if (result != null) {
                        Icon(
                            if (result.success) Icons.Filled.CheckCircle else Icons.Filled.Error,
                            contentDescription = null, modifier = Modifier.size(10.dp),
                            tint = if (result.success) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                        )
                    } else {
                        CircularProgressIndicator(modifier = Modifier.size(10.dp), strokeWidth = 1.dp)
                    }
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(call.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSecondaryContainer)
                }
            }
        }
    }
}

@Composable
private fun LoadingIndicator() {
    Row(horizontalArrangement = Arrangement.Start, modifier = Modifier.fillMaxWidth()) {
        val infiniteTransition = rememberInfiniteTransition(label = "dots")
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
            Row(modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                repeat(3) { index ->
                    val alpha by infiniteTransition.animateFloat(
                        initialValue = 0.3f, targetValue = 1f,
                        animationSpec = infiniteRepeatable(animation = tween(600, delayMillis = index * 200), repeatMode = RepeatMode.Reverse),
                        label = "dot-$index",
                    )
                    Box(Modifier.size(6.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = alpha)))
                }
            }
        }
    }
}

// ──── Compact empty state ────

@Composable
private fun EmptyChatState(
    hasProvider: Boolean,
    onNavigateSettings: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Filled.AutoAwesome,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f),
            modifier = Modifier.size(36.dp),
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text("How can I help you?", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(4.dp))
        if (hasProvider) {
            Text(
                "Ask anything — I have tools for calculations,\nweb lookups, device control, and more.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        } else {
            Text(
                "Pick a provider first to start chatting.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(10.dp))
            FilledTonalButton(onClick = onNavigateSettings) {
                Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(14.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Setup Provider")
            }
        }
    }
}

@Composable
private fun MessageDateSeparator(timestamp: Long) {
    val date = remember(timestamp) {
        DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(timestamp))
    }
    Box(modifier = Modifier.fillMaxWidth()) {
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.55f),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.align(Alignment.Center),
        ) {
            Text(
                text = date,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                color = MaterialTheme.colorScheme.onSecondaryContainer,
            )
        }
    }
}

private fun isSameCalendarDay(first: Long, second: Long): Boolean {
    if (first == second) return true
    val calA = Calendar.getInstance()
    val calB = Calendar.getInstance()
    calA.timeInMillis = first
    calB.timeInMillis = second
    return calA.get(Calendar.YEAR) == calB.get(Calendar.YEAR) &&
        calA.get(Calendar.DAY_OF_YEAR) == calB.get(Calendar.DAY_OF_YEAR)
}

private fun isSupportedChatAttachment(attachment: MessageAttachment): Boolean {
    val mime = attachment.mimeType.lowercase()
    val name = attachment.name.lowercase()
    return when {
        mime.startsWith("image/") -> true
        mime.startsWith("text/") -> true
        mime == "application/json" -> true
        mime == "application/pdf" -> true
        name.endsWith(".md") || name.endsWith(".csv") || name.endsWith(".log") || name.endsWith(".xml") || name.endsWith(".yaml") || name.endsWith(".yml") || name.endsWith(".txt") -> true
        else -> false
    }
}

@Composable
private fun ErrorBanner(error: String, onDismiss: () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(6.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 2.dp),
    ) {
        Row(modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Warning, contentDescription = "Error", tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text(error, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.weight(1f))
            IconButton(onClick = onDismiss, modifier = Modifier.size(20.dp)) {
                Icon(Icons.Filled.Close, contentDescription = "Dismiss", tint = MaterialTheme.colorScheme.onErrorContainer, modifier = Modifier.size(14.dp))
            }
        }
    }
}

@Composable
private fun TokenUsageBar(usage: TokenUsage) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f), modifier = Modifier.fillMaxWidth()) {
        Row(modifier = Modifier.padding(horizontal = 10.dp, vertical = 2.dp), horizontalArrangement = Arrangement.End) {
            Text(
                "Latest turn · prompt ${usage.promptTokens} · completion ${usage.completionTokens} · total ${usage.totalTokens}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ──── Compact input bar ────

@Composable
private fun ChatInputBar(
    value: String,
    onValueChange: (String) -> Unit,
    attachments: List<MessageAttachment>,
    onAttachmentsChanged: (List<MessageAttachment>) -> Unit,
    onSend: () -> Unit,
    isStreaming: Boolean,
    sendDisabledReason: String? = null,
    onCancel: () -> Unit,
    promptTemplates: List<PromptTemplate>,
    onInsertPrompt: (PromptTemplate) -> Unit,
) {
    var showPromptLibrary by remember { mutableStateOf(false) }
    var showAllAttachments by remember { mutableStateOf(false) }
    var pickerHint by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val maxAttachments = 8
    val attachmentPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetMultipleContents(),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        val parsed = uris.mapNotNull { uri ->
            runCatching { context.toMessageAttachment(uri) }.getOrNull()
        }
        if (parsed.isEmpty()) {
            Toast.makeText(context, "No valid attachments were selected", Toast.LENGTH_SHORT).show()
            return@rememberLauncherForActivityResult
        }
        val supported = parsed.filter { isSupportedChatAttachment(it) }
        val rejected = parsed.filterNot { isSupportedChatAttachment(it) }
        if (rejected.isNotEmpty()) {
            pickerHint = "Unsupported files skipped: ${rejected.joinToString(", ") { it.name }}"
        }
        val next = (attachments + supported).take(maxAttachments)
        val skipped = (attachments + parsed).size - next.size
        if (supported.isEmpty()) {
            if (rejected.isNotEmpty()) {
                pickerHint = "No supported files in selection."
            } else {
                pickerHint = null
            }
            return@rememberLauncherForActivityResult
        }
        if (skipped > 0) {
            pickerHint = "Attachment limit is $maxAttachments. Extra files were ignored."
        }
        if (skipped == 0 && rejected.isEmpty()) pickerHint = null
        onAttachmentsChanged(next)
    }
    Surface(
        tonalElevation = 2.dp,
        shadowElevation = 4.dp,
        color = MaterialTheme.colorScheme.surface,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            IconButton(
                onClick = { showPromptLibrary = true },
                modifier = Modifier.size(36.dp),
                enabled = promptTemplates.isNotEmpty(),
            ) {
                BadgedBox(
                    badge = {
                        if (promptTemplates.isNotEmpty()) {
                            Badge(
                                containerColor = MaterialTheme.colorScheme.primary,
                                contentColor = MaterialTheme.colorScheme.onPrimary,
                            ) {
                                Text(min(promptTemplates.size, 99).toString(), style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    },
                ) {
                    Icon(
                        Icons.Filled.Article,
                        contentDescription = "Prompt template library",
                        tint = if (promptTemplates.isNotEmpty()) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
            IconButton(
                onClick = { attachmentPicker.launch("*/*") },
                modifier = Modifier.size(36.dp),
                enabled = !isStreaming,
            ) {
                Icon(Icons.Filled.AttachFile, contentDescription = "Attach", modifier = Modifier.size(20.dp))
            }
            Column(modifier = Modifier.weight(1f)) {
                if (attachments.isNotEmpty()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        attachments.take(3).forEach { attachment ->
                            AssistChip(
                                onClick = {},
                                label = {
                                    Column {
                                        Text(attachment.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(
                                            if (attachment.kind == "image") "Vision" else "File",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                },
                                leadingIcon = { Icon(if (attachment.kind == "image") Icons.Filled.Image else Icons.Filled.AttachFile, contentDescription = null, modifier = Modifier.size(14.dp)) },
                                trailingIcon = {
                                    IconButton(
                                        onClick = {
                                            onAttachmentsChanged(attachments - attachment)
                                            pickerHint = null
                                        },
                                        modifier = Modifier.size(20.dp),
                                    ) { Icon(Icons.Filled.Close, contentDescription = "Remove", modifier = Modifier.size(14.dp)) }
                                },
                                modifier = Modifier.weight(1f, fill = false).height(32.dp),
                            )
                        }
                        if (attachments.size > 3) {
                            AssistChip(
                                onClick = { showAllAttachments = true },
                                label = { Text("+${attachments.size - 3} more") },
                                modifier = Modifier.height(32.dp),
                            )
                        }
                    }
                }
                pickerHint?.let { hint ->
                    Text(
                        hint,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(bottom = 4.dp),
                    )
                }
                OutlinedTextField(
                    value = value,
                    onValueChange = onValueChange,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isStreaming && sendDisabledReason == null,
                    label = if (isStreaming) {
                        { Text("Draft locked while generating. Cancel to edit.") }
                    } else if (sendDisabledReason != null) {
                        { Text(sendDisabledReason, color = MaterialTheme.colorScheme.error, maxLines = 1) }
                    } else null,
                    placeholder = { Text("Message…") },
                    maxLines = 4,
                    shape = RoundedCornerShape(20.dp),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                    keyboardActions = KeyboardActions(
                        onSend = {
                            if (sendDisabledReason == null && (value.isNotBlank() || attachments.isNotEmpty()) && !isStreaming) {
                                onSend()
                            }
                        },
                    ),
                )
            }

            if (isStreaming) {
                FilledIconButton(
                    onClick = onCancel,
                    modifier = Modifier.size(36.dp),
                    shape = CircleShape,
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer,
                    ),
                ) {
                    Icon(Icons.Filled.Stop, contentDescription = "Stop", modifier = Modifier.size(18.dp))
                }
            } else {
                FilledIconButton(
                    onClick = onSend,
                    modifier = Modifier.size(36.dp),
                    shape = CircleShape,
                    enabled = sendDisabledReason == null && !isStreaming && (value.isNotBlank() || attachments.isNotEmpty()),
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                        disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                        disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
                    ),
                ) {
                    Icon(Icons.Filled.ArrowUpward, contentDescription = "Send", modifier = Modifier.size(18.dp))
                }
            }
        }
    }

        if (showAllAttachments) {
        AlertDialog(
            onDismissRequest = { showAllAttachments = false },
            title = { Text("Attachments") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    attachments.forEach { attachment ->
                        Surface(
                            onClick = { openMessageAttachment(context, attachment) },
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(
                                    if (attachment.kind == "image") Icons.Filled.Image else Icons.Filled.AttachFile,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                                Spacer(Modifier.width(8.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(attachment.name, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(attachment.mimeType, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                IconButton(onClick = {
                                    onAttachmentsChanged(attachments - attachment)
                                    pickerHint = null
                                }, modifier = Modifier.size(20.dp)) {
                                    Icon(Icons.Filled.Close, contentDescription = "Remove", modifier = Modifier.size(12.dp))
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showAllAttachments = false }) { Text("Done") } },
        )
    }

    if (showPromptLibrary) {
        PromptLibrarySheet(
            templates = promptTemplates,
            onDismiss = { showPromptLibrary = false },
            onSelect = { template ->
                onInsertPrompt(template)
                showPromptLibrary = false
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PromptLibrarySheet(
    templates: List<PromptTemplate>,
    onDismiss: () -> Unit,
    onSelect: (PromptTemplate) -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            Text("Prompt Library", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(8.dp))
            LazyColumn(
                modifier = Modifier.heightIn(max = 360.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(templates, key = { it.id.value }) { template ->
                    Surface(
                        onClick = { onSelect(template) },
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(modifier = Modifier.padding(10.dp)) {
                            Text(template.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(template.body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
        }
    }
}
