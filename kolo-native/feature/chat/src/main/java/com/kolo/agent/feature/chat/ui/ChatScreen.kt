package com.kolo.agent.feature.chat.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    state: ChatUiState,
    onSendMessage: (String, List<MessageAttachment>) -> Unit,
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
    folders: List<Folder>,
    activeFolderId: FolderId?,
    searchQuery: String,
    currentChatId: ChatId?,
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

        // New chat button
        FilledTonalButton(
            onClick = onNewChat,
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
            textStyle = MaterialTheme.typography.bodySmall,
        )

        LazyColumn(
            modifier = Modifier.fillMaxWidth().heightIn(max = 116.dp),
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
        ) {
            item {
                NavigationDrawerItem(
                    label = { Text("All chats", style = MaterialTheme.typography.bodySmall) },
                    icon = { Icon(Icons.Filled.Forum, contentDescription = null, modifier = Modifier.size(16.dp)) },
                    selected = activeFolderId == null,
                    onClick = { onSetActiveFolder(null) },
                    modifier = Modifier.padding(vertical = 1.dp),
                )
            }
            items(folders, key = { it.id.value }) { folder ->
                NavigationDrawerItem(
                    label = { Text(folder.name, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    icon = { Icon(Icons.Filled.Folder, contentDescription = null, modifier = Modifier.size(16.dp)) },
                    selected = activeFolderId == folder.id,
                    onClick = { onSetActiveFolder(folder.id) },
                    badge = {
                        IconButton(onClick = { onDeleteFolder(folder.id) }, modifier = Modifier.size(24.dp)) {
                            Icon(Icons.Filled.Close, contentDescription = "Delete folder", modifier = Modifier.size(12.dp))
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
                var menuExpanded by remember { mutableStateOf(false) }
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
                        Box {
                            IconButton(onClick = { menuExpanded = true }, modifier = Modifier.size(28.dp)) {
                                Icon(Icons.Filled.MoreVert, contentDescription = "Chat actions", modifier = Modifier.size(15.dp))
                            }
                            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                                DropdownMenuItem(
                                    text = { Text(if (chat.isPinned) "Unpin" else "Pin") },
                                    leadingIcon = { Icon(Icons.Filled.PushPin, contentDescription = null) },
                                    onClick = {
                                        menuExpanded = false
                                        onSetPinned(chat.id, !chat.isPinned)
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text("No folder") },
                                    leadingIcon = { Icon(Icons.Filled.FolderOff, contentDescription = null) },
                                    onClick = {
                                        menuExpanded = false
                                        onMoveChat(chat.id, null)
                                    },
                                )
                                folders.forEach { folder ->
                                    DropdownMenuItem(
                                        text = { Text(folder.name) },
                                        leadingIcon = { Icon(Icons.Filled.Folder, contentDescription = null) },
                                        onClick = {
                                            menuExpanded = false
                                            onMoveChat(chat.id, folder.id)
                                        },
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text("Delete") },
                                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
                                    onClick = {
                                        menuExpanded = false
                                        onDeleteChat(chat.id)
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
                OutlinedTextField(
                    value = folderDraft,
                    onValueChange = { folderDraft = it },
                    label = { Text("Folder name") },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onCreateFolder(folderDraft)
                        folderDraft = ""
                        showFolderDialog = false
                    },
                    enabled = folderDraft.isNotBlank(),
                ) { Text("Create") }
            },
            dismissButton = { TextButton(onClick = { showFolderDialog = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun ChatContent(
    state: ChatUiState,
    onSendMessage: (String, List<MessageAttachment>) -> Unit,
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
    var inputText by remember { mutableStateOf("") }
    var pendingAttachments by remember { mutableStateOf<List<MessageAttachment>>(emptyList()) }
    val listState = rememberLazyListState()

    // Auto-scroll to bottom on new messages
    LaunchedEffect(state.messages.size, state.streamingContent) {
        if (state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.size)
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
                        onSendMessage(inputText.trim(), pendingAttachments)
                        inputText = ""
                        pendingAttachments = emptyList()
                    }
                },
                isStreaming = state.isStreaming,
                onCancel = onCancel,
                promptTemplates = state.promptTemplates,
                onInsertPrompt = { template ->
                    inputText = if (inputText.isBlank()) template.body else "${inputText.trimEnd()}\n\n${template.body}"
                    onUsePromptTemplate(template.id)
                },
            )
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
                verticalArrangement = Arrangement.spacedBy(4.dp),
                contentPadding = PaddingValues(vertical = 6.dp),
            ) {
                items(state.messages) { message ->
                    MessageBubble(message = message)
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
                    item { EmptyChatState() }
                }
            }

            // Token usage
            state.tokenUsage?.let { usage ->
                TokenUsageBar(usage = usage)
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
) {
    var expanded by remember { mutableStateOf(false) }
    val models = providerConfig?.models.orEmpty()
    val hasProvider = providerConfig != null
    val isLocalProvider = providerConfig?.isLocal == true
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
                        text = provider,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        lineHeight = 14.sp,
                    )
                }
            }
            if (hasProvider) {
                Box {
                    IconButton(onClick = { expanded = true }, modifier = Modifier.size(40.dp)) {
                        Icon(Icons.Filled.ArrowDropDown, contentDescription = "Model picker", modifier = Modifier.size(24.dp))
                    }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        if (models.isEmpty()) {
                            DropdownMenuItem(
                                text = { Text(model ?: if (isLocalProvider) "Local model" else "No models loaded") },
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
                            models.forEach { option ->
                                DropdownMenuItem(
                                    text = { Text(option.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                    leadingIcon = {
                                        if (option.modelId == providerConfig?.activeModel?.modelId) {
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
                        HorizontalDivider()
                        if (!isLocalProvider) {
                            DropdownMenuItem(
                                text = { Text(if (models.isEmpty()) "Fetch models" else "Refresh models") },
                                leadingIcon = {
                                    Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                                },
                                onClick = {
                                    expanded = false
                                    onRefreshActiveModels()
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(if (isLocalProvider) "Local model settings" else "Provider settings") },
                            leadingIcon = {
                                Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(18.dp))
                            },
                            onClick = {
                                expanded = false
                                onSettings()
                            },
                        )
                    }
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
private fun MessageBubble(message: Message) {
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
            shape = RoundedCornerShape(
                topStart = 14.dp,
                topEnd = 14.dp,
                bottomStart = if (isUser) 14.dp else 2.dp,
                bottomEnd = if (isUser) 2.dp else 14.dp,
            ),
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
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        message.attachments.forEach { attachment ->
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(
                                        if (isUser) MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.14f)
                                        else MaterialTheme.colorScheme.surface.copy(alpha = 0.72f)
                                    )
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
                                )
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
private fun EmptyChatState() {
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
        Text(
            "Ask anything — I have tools for calculations,\nweb lookups, device control, and more.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
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
            Text("${usage.promptTokens}↑ ${usage.completionTokens}↓ ${usage.totalTokens}Σ", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
    onCancel: () -> Unit,
    promptTemplates: List<PromptTemplate>,
    onInsertPrompt: (PromptTemplate) -> Unit,
) {
    var showPromptLibrary by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val attachmentPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetMultipleContents(),
    ) { uris ->
        if (uris.isNotEmpty()) {
            onAttachmentsChanged((attachments + uris.map { context.toMessageAttachment(it) }).take(8))
        }
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
                Icon(
                    Icons.Filled.Article,
                    contentDescription = "Prompt library",
                    tint = if (promptTemplates.isNotEmpty()) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
                    modifier = Modifier.size(20.dp),
                )
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
                                label = { Text(attachment.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                leadingIcon = { Icon(if (attachment.kind == "image") Icons.Filled.Image else Icons.Filled.AttachFile, contentDescription = null, modifier = Modifier.size(14.dp)) },
                                trailingIcon = {
                                    IconButton(
                                        onClick = { onAttachmentsChanged(attachments - attachment) },
                                        modifier = Modifier.size(18.dp),
                                    ) { Icon(Icons.Filled.Close, contentDescription = "Remove", modifier = Modifier.size(12.dp)) }
                                },
                                modifier = Modifier.weight(1f, fill = false).height(32.dp),
                            )
                        }
                        if (attachments.size > 3) {
                            AssistChip(onClick = {}, label = { Text("+${attachments.size - 3}") }, modifier = Modifier.height(32.dp))
                        }
                    }
                }
                OutlinedTextField(
                    value = value,
                    onValueChange = onValueChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Message…") },
                    maxLines = 4,
                    shape = RoundedCornerShape(20.dp),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                    keyboardActions = KeyboardActions(
                        onSend = {
                            if ((value.isNotBlank() || attachments.isNotEmpty()) && !isStreaming) {
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
                    enabled = value.isNotBlank() || attachments.isNotEmpty(),
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
