package com.kolo.agent.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kolo.agent.core.settings.AppSettings
import com.kolo.agent.core.database.repository.RoomMemoryRepository
import com.kolo.agent.core.model.Memory
import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.ProviderId
import com.kolo.agent.core.model.ToolPermissionMode
import com.kolo.agent.core.providers.ProviderRepository
import com.kolo.agent.core.tools.permissions.ToolPermissionStore
import com.kolo.agent.core.tools.registry.ToolRegistry
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ToolPermissionUi(
    val name: String,
    val displayName: String,
    val defaultMode: ToolPermissionMode,
    val currentMode: ToolPermissionMode,
    val isDangerous: Boolean = false,
)

data class SettingsUiState(
    val providers: List<ProviderConfig> = emptyList(),
    val activeProviderId: ProviderId? = null,
    val toolPermissions: List<ToolPermissionUi> = emptyList(),
    val memories: List<Memory> = emptyList(),
    val themeMode: AppThemeMode = AppThemeMode.SYSTEM,
)

enum class AppThemeMode { SYSTEM, LIGHT, DARK }

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val providerRepository: ProviderRepository,
    private val toolRegistry: ToolRegistry,
    private val permissionStore: ToolPermissionStore,
    private val memoryRepository: RoomMemoryRepository,
    private val appSettings: AppSettings,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        loadProviders()
        loadToolPermissions()
        loadMemories()
        loadTheme()
    }

    private fun loadProviders() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                providers = providerRepository.getAllProviders(),
            )
            providerRepository.getActiveProvider()?.let {
                _uiState.value = _uiState.value.copy(activeProviderId = it.id)
            }
        }
    }

    private fun loadToolPermissions() {
        viewModelScope.launch {
            // Collect permission overrides and combine with defaults
            permissionStore.allOverrides().collect { overrides ->
                val tools = toolRegistry.getAllTools()
                val permUiList = tools.map { tool ->
                    val currentMode = overrides[tool.name]
                        ?: toolRegistry.getDefaultPermissionMode(tool.name)
                    ToolPermissionUi(
                        name = tool.name,
                        displayName = tool.name.replace("_", " ").replaceFirstChar { it.uppercase() },
                        defaultMode = toolRegistry.getDefaultPermissionMode(tool.name),
                        currentMode = currentMode,
                        isDangerous = tool.permission == com.kolo.agent.core.model.ToolPermission.dangerous,
                    )
                }
                _uiState.value = _uiState.value.copy(toolPermissions = permUiList)
            }
        }
    }

    private fun loadMemories() {
        viewModelScope.launch {
            val memories = memoryRepository.getAll()
            _uiState.value = _uiState.value.copy(memories = memories)
        }
    }

    private fun loadTheme() {
        viewModelScope.launch {
            appSettings.themeMode.collect { mode ->
                val uiMode = when (mode) {
                    AppSettings.ThemeMode.SYSTEM -> AppThemeMode.SYSTEM
                    AppSettings.ThemeMode.LIGHT -> AppThemeMode.LIGHT
                    AppSettings.ThemeMode.DARK -> AppThemeMode.DARK
                }
                _uiState.value = _uiState.value.copy(themeMode = uiMode)
            }
        }
    }

    fun setThemeMode(mode: AppThemeMode) {
        viewModelScope.launch {
            val settingsMode = when (mode) {
                AppThemeMode.SYSTEM -> AppSettings.ThemeMode.SYSTEM
                AppThemeMode.LIGHT -> AppSettings.ThemeMode.LIGHT
                AppThemeMode.DARK -> AppSettings.ThemeMode.DARK
            }
            appSettings.setThemeMode(settingsMode)
        }
    }

    fun setToolPermission(toolName: String, mode: ToolPermissionMode) {
        viewModelScope.launch {
            if (mode == toolRegistry.getDefaultPermissionMode(toolName)) {
                // Reset to default — remove override
                permissionStore.resetMode(toolName)
            } else {
                permissionStore.setMode(toolName, mode)
            }
        }
    }

    fun addMemory(content: String, kind: String = "fact") {
        viewModelScope.launch {
            val memory = Memory(
                kind = kind,
                content = content,
            )
            memoryRepository.save(memory)
            loadMemories()
        }
    }

    fun deleteMemory(memoryId: String) {
        viewModelScope.launch {
            memoryRepository.deleteById(memoryId)
            loadMemories()
        }
    }

    fun addProvider(config: ProviderConfig, apiKey: String) {
        viewModelScope.launch {
            providerRepository.saveProvider(config, apiKey)
            _uiState.value = _uiState.value.copy(
                providers = providerRepository.getAllProviders(),
            )
            _uiState.value = _uiState.value.copy(
                activeProviderId = providerRepository.getActiveProvider()?.id,
            )
        }
    }

    fun deleteProvider(id: ProviderId) {
        viewModelScope.launch {
            providerRepository.deleteProvider(id)
            _uiState.value = _uiState.value.copy(
                providers = providerRepository.getAllProviders(),
            )
            if (_uiState.value.activeProviderId == id) {
                _uiState.value = _uiState.value.copy(
                    activeProviderId = providerRepository.getActiveProvider()?.id,
                )
            }
        }
    }

    fun setActiveProvider(id: ProviderId) {
        viewModelScope.launch {
            val currentProviders = providerRepository.getAllProviders()
            val updated = currentProviders.map { config ->
                config.copy(isActive = config.id == id)
            }
            for (config in updated) {
                val key = providerRepository.getApiKey(config.id.value)
                providerRepository.saveProvider(config, key)
            }
            _uiState.value = _uiState.value.copy(
                providers = providerRepository.getAllProviders(),
                activeProviderId = id,
            )
        }
    }
}