package com.kolo.agent

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.*
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.*
import com.kolo.agent.core.model.*
import com.kolo.agent.feature.chat.ui.ChatScreen
import com.kolo.agent.feature.chat.ChatViewModel
import com.kolo.agent.feature.chat.ToolApprovalAction
import com.kolo.agent.feature.settings.ui.SettingsScreen
import com.kolo.agent.feature.settings.ui.LocalModelScreen
import com.kolo.agent.feature.settings.SettingsViewModel
import com.kolo.agent.feature.settings.LocalModelViewModel
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            KoloTheme {
                KoloNavApp()
            }
        }
    }
}

@Composable
fun KoloNavApp() {
    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = "chat",
    ) {
        composable("chat") {
            val chatViewModel: ChatViewModel = hiltViewModel()
            val state by chatViewModel.uiState.collectAsState()
            ChatScreen(
                state = state,
                onSendMessage = { text, attachments -> chatViewModel.sendMessage(text, attachments) },
                onCancel = { chatViewModel.cancelGeneration() },
                onClearError = { chatViewModel.clearError() },
                onSelectChat = { chatViewModel.loadChat(it) },
                onNewChat = { chatViewModel.newChat() },
                onDeleteChat = { chatViewModel.deleteChat(it) },
                onSetChatSearchQuery = { chatViewModel.setChatSearchQuery(it) },
                onSetActiveFolder = { chatViewModel.setActiveFolder(it) },
                onCreateFolder = { chatViewModel.createFolder(it) },
                onDeleteFolder = { chatViewModel.deleteFolder(it) },
                onMoveChat = { chatId, folderId -> chatViewModel.moveChat(chatId, folderId) },
                onSetPinned = { chatId, pinned -> chatViewModel.setPinned(chatId, pinned) },
                onNavigateSettings = { navController.navigate("settings") },
                onSetActiveModel = { modelId -> chatViewModel.setActiveModel(modelId) },
                onRefreshActiveModels = { chatViewModel.refreshActiveProviderModels() },
                onUsePromptTemplate = { templateId -> chatViewModel.touchPromptTemplate(templateId) },
                onAllowOnce = { chatViewModel.handleApprovalAction(ToolApprovalAction.AllowOnce(it)) },
                onAlwaysAllow = { chatViewModel.handleApprovalAction(ToolApprovalAction.AlwaysAllow(it)) },
                onDenyOnce = { chatViewModel.handleApprovalAction(ToolApprovalAction.DenyOnce(it)) },
                onBlock = { chatViewModel.handleApprovalAction(ToolApprovalAction.Block(it)) },
            )
        }
        composable("settings") {
            val settingsViewModel: SettingsViewModel = hiltViewModel()
            val state by settingsViewModel.uiState.collectAsState()
            SettingsScreen(
                state = state,
                onAddProvider = { config, apiKey -> settingsViewModel.addProvider(config, apiKey) },
                onUpdateProvider = { config, apiKey -> settingsViewModel.updateProvider(config, apiKey) },
                onDeleteProvider = { id -> settingsViewModel.deleteProvider(id) },
                onSetActiveProvider = { id -> settingsViewModel.setActiveProvider(id) },
                onSetProviderActiveModel = { id, modelId -> settingsViewModel.setActiveProviderModel(id, modelId) },
                onSetProviderModelPath = { id, path -> settingsViewModel.setProviderModelPath(id, path) },
                onRefreshProviderModels = { id -> settingsViewModel.refreshProviderModels(id) },
                onSetToolPermission = { name, mode -> settingsViewModel.setToolPermission(name, mode) },
                onAddMemory = { content, kind -> settingsViewModel.addMemory(content, kind) },
                onDeleteMemory = { id -> settingsViewModel.deleteMemory(id) },
                onSetCustomInstructions = { value -> settingsViewModel.setCustomInstructions(value) },
                onSaveCustomTool = { tool -> settingsViewModel.saveCustomTool(tool) },
                onDeleteCustomTool = { id -> settingsViewModel.deleteCustomTool(id) },
                onSaveSkill = { skill -> settingsViewModel.saveSkill(skill) },
                onDeleteSkill = { id -> settingsViewModel.deleteSkill(id) },
                onSetSkillEnabled = { id, enabled -> settingsViewModel.setSkillEnabled(id, enabled) },
                onSetTheme = { mode -> settingsViewModel.setThemeMode(mode) },
                onSetLocalLlamaGpuMode = { useGpu -> settingsViewModel.setLocalLlamaGpuMode(useGpu) },
                onNavigateLocalModels = { navController.navigate("local_models") },
                onNavigateBack = { navController.popBackStack() },
            )
        }
        composable("local_models") {
            val localModelViewModel: LocalModelViewModel = hiltViewModel()
            val state by localModelViewModel.uiState.collectAsState()
            LocalModelScreen(
                state = state,
                onImportModel = { uri -> localModelViewModel.importModel(uri) },
                onDeleteModel = { model -> localModelViewModel.deleteModel(model) },
                onSetActiveModel = { model -> localModelViewModel.setActiveModel(model) },
                onClearImportStatus = { localModelViewModel.clearImportStatus() },
                onConfirmDelete = { model -> localModelViewModel.confirmDelete(model) },
                onDismissDeleteConfirm = { localModelViewModel.dismissDeleteConfirm() },
                onEnsureLocalProvider = { localModelViewModel.ensureLocalProvider() },
                onNavigateBack = { navController.popBackStack() },
            )
        }
    }
}
