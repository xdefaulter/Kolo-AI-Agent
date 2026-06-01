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
                onSendMessage = { chatViewModel.sendMessage(it) },
                onCancel = { chatViewModel.cancelGeneration() },
                onClearError = { chatViewModel.clearError() },
                onSelectChat = { chatViewModel.loadChat(it) },
                onNewChat = { chatViewModel.newChat() },
                onDeleteChat = { chatViewModel.deleteChat(it) },
                onNavigateSettings = { navController.navigate("settings") },
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
                onDeleteProvider = { id -> settingsViewModel.deleteProvider(id) },
                onSetActiveProvider = { id -> settingsViewModel.setActiveProvider(id) },
                onSetProviderModelPath = { id, path -> settingsViewModel.setProviderModelPath(id, path) },
                onSetToolPermission = { name, mode -> settingsViewModel.setToolPermission(name, mode) },
                onAddMemory = { content, kind -> settingsViewModel.addMemory(content, kind) },
                onDeleteMemory = { id -> settingsViewModel.deleteMemory(id) },
                onSetTheme = { mode -> settingsViewModel.setThemeMode(mode) },
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
