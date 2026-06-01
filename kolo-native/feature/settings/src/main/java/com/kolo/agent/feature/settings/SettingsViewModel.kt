package com.kolo.agent.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kolo.agent.core.providers.local.LocalModelManager
import com.kolo.agent.core.settings.AppSettings
import com.kolo.agent.core.database.repository.RoomMemoryRepository
import com.kolo.agent.core.model.Memory
import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.ProviderId
import com.kolo.agent.core.model.ModelConfig
import com.kolo.agent.core.model.CustomToolDef
import com.kolo.agent.core.model.Skill
import com.kolo.agent.core.model.ToolPermissionMode
import com.kolo.agent.core.providers.ProviderRepository
import com.kolo.agent.core.providers.openai.OpenAiStreamClient
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
    val localLlamaModelPath: String = "",
    val localLlamaGpuLayers: Int = 0,
    val bridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown,
    val modelFetchStatus: Map<String, String> = emptyMap(),
    val customInstructions: String = "",
    val customTools: List<CustomToolDef> = emptyList(),
    val skills: List<Skill> = emptyList(),
)

enum class AppThemeMode { SYSTEM, LIGHT, DARK }

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val providerRepository: ProviderRepository,
    private val toolRegistry: ToolRegistry,
    private val permissionStore: ToolPermissionStore,
    private val memoryRepository: RoomMemoryRepository,
    private val appSettings: AppSettings,
    private val localModelManager: LocalModelManager,
    private val streamClient: OpenAiStreamClient,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        loadProviders()
        loadToolPermissions()
        loadMemories()
        loadTheme()
        loadLocalSettings()
        loadCustomInstructions()
        loadCustomToolsAndSkills()
    }

    private fun loadProviders() {
        viewModelScope.launch {
            providerRepository.providersFlow.collect { providers ->
                _uiState.value = _uiState.value.copy(
                    providers = providers,
                    activeProviderId = providers.firstOrNull { it.isActive }?.id,
                )
            }
        }
    }

    private fun loadToolPermissions() {
        viewModelScope.launch {
            permissionStore.allOverrides().combine(appSettings.customTools) { overrides, customTools ->
                toolRegistry.setCustomTools(customTools)
                val tools = toolRegistry.getAllTools()
                tools.map { tool ->
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
            }.collect { permUiList ->
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

    private fun loadLocalSettings() {
        viewModelScope.launch {
            // Check bridge off main thread
            localModelManager.checkBridgeAvailability()
            // Collect bridge status
            launch { localModelManager.bridgeStatus.collect { status ->
                _uiState.value = _uiState.value.copy(bridgeStatus = status)
            } }
            // Collect active model path
            launch { appSettings.localLlamaModelPath.collect { path ->
                _uiState.value = _uiState.value.copy(localLlamaModelPath = path.orEmpty())
            } }
            launch { appSettings.localLlamaGpuLayers.collect { gpuLayers ->
                _uiState.value = _uiState.value.copy(localLlamaGpuLayers = gpuLayers)
            } }
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
                permissionStore.resetMode(toolName)
            } else {
                permissionStore.setMode(toolName, mode)
            }
        }
    }

    private fun loadCustomInstructions() {
        viewModelScope.launch {
            appSettings.customInstructions.collect { instructions ->
                _uiState.value = _uiState.value.copy(customInstructions = instructions)
            }
        }
    }

    fun setCustomInstructions(value: String) {
        viewModelScope.launch {
            appSettings.setCustomInstructions(value)
        }
    }

    private fun loadCustomToolsAndSkills() {
        viewModelScope.launch {
            launch {
                appSettings.customTools.collect { tools ->
                    _uiState.value = _uiState.value.copy(customTools = tools)
                }
            }
            launch {
                appSettings.skills.collect { skills ->
                    toolRegistry.setSkills(skills)
                    _uiState.value = _uiState.value.copy(skills = skills)
                }
            }
        }
    }

    fun saveCustomTool(tool: CustomToolDef) {
        viewModelScope.launch {
            appSettings.saveCustomTool(tool)
        }
    }

    fun deleteCustomTool(id: String) {
        viewModelScope.launch {
            appSettings.deleteCustomTool(id)
        }
    }

    fun saveSkill(skill: Skill) {
        viewModelScope.launch {
            appSettings.saveSkill(skill)
        }
    }

    fun deleteSkill(id: String) {
        viewModelScope.launch {
            appSettings.deleteSkill(id)
        }
    }

    fun setSkillEnabled(id: String, enabled: Boolean) {
        viewModelScope.launch {
            appSettings.setSkillEnabled(id, enabled)
        }
    }

    fun addMemory(content: String, kind: String = "fact") {
        viewModelScope.launch {
            val memory = Memory(kind = kind, content = content)
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
            var configToSave = config
            if (!config.isLocal) {
                configToSave = fetchModelsForProvider(config, apiKey) ?: config
            }
            providerRepository.saveProvider(configToSave, apiKey)
            if (configToSave.isLocal && !configToSave.modelPath.isNullOrBlank()) {
                appSettings.setLocalLlamaModelPath(configToSave.modelPath)
            }
            refreshProvidersState()
        }
    }

    fun updateProvider(config: ProviderConfig, apiKey: String? = null) {
        viewModelScope.launch {
            val key = apiKey ?: providerRepository.getApiKey(config.id.value)
            val existingProvider = providerRepository.getAllProviders().firstOrNull { it.id == config.id }
            var configToSave = config.copy(updatedAt = System.currentTimeMillis())
            val shouldRefreshModels = if (configToSave.isLocal) {
                false
            } else {
                val endpointChanged = existingProvider == null ||
                    existingProvider.baseUrl != configToSave.baseUrl ||
                    existingProvider.modelsEndpoint != configToSave.modelsEndpoint ||
                    existingProvider.kind != configToSave.kind
                configToSave.models.isEmpty() || endpointChanged
            }
            if (shouldRefreshModels) {
                configToSave = fetchModelsForProvider(configToSave, key) ?: configToSave
            }
            providerRepository.saveProvider(configToSave, key)
            refreshProvidersState()
        }
    }

    fun deleteProvider(id: ProviderId) {
        viewModelScope.launch {
            providerRepository.deleteProvider(id)
        }
    }

    fun setActiveProvider(id: ProviderId) {
        viewModelScope.launch {
            providerRepository.setActiveProvider(id)
            val provider = providerRepository.getAllProviders().firstOrNull { it.id == id }
            if (provider != null && !provider.isLocal && provider.models.isEmpty()) {
                refreshProviderModels(id)
            }
        }
    }

    fun refreshProviderModels(id: ProviderId) {
        viewModelScope.launch {
            val provider = providerRepository.getAllProviders().firstOrNull { it.id == id } ?: return@launch
            if (provider.isLocal) return@launch
            val apiKey = providerRepository.getApiKey(id.value)
            fetchModelsForProvider(provider, apiKey)?.let { updated ->
                providerRepository.saveProvider(updated, apiKey)
            }
            refreshProvidersState()
        }
    }

    fun setActiveProviderModel(providerId: ProviderId, modelId: String) {
        viewModelScope.launch {
            providerRepository.setActiveModel(providerId, modelId)
            refreshProvidersState()
        }
    }

    fun setLocalLlamaGpuMode(useGpu: Boolean) {
        viewModelScope.launch {
            appSettings.setLocalLlamaGpuLayers(if (useGpu) 999 else 0)
        }
    }

    fun setProviderModelPath(id: ProviderId, modelPath: String) {
        viewModelScope.launch {
            val providers = providerRepository.getAllProviders()
            val provider = providers.firstOrNull { it.id == id } ?: return@launch
            val cleanPath = modelPath.trim()
            val updated = provider.copy(
                modelPath = cleanPath.ifBlank { null },
                updatedAt = System.currentTimeMillis(),
            )
            providerRepository.saveProvider(updated, providerRepository.getApiKey(id.value))
            if (updated.isLocal) {
                appSettings.setLocalLlamaModelPath(updated.modelPath)
            }
            _uiState.value = _uiState.value.copy(
                providers = providerRepository.getAllProviders(),
            )
        }
    }

    private suspend fun fetchModelsForProvider(provider: ProviderConfig, apiKey: String): ProviderConfig? {
        setModelFetchStatus(provider.id.value, "Fetching models...")
        com.kolo.agent.core.providers.ProviderConfigKeyStore[provider.id.value] = apiKey
        return try {
            val fetched = streamClient.fetchModels(provider)
                .distinctBy { it.first }
                .sortedBy { it.first }
            if (fetched.isEmpty()) {
                setModelFetchStatus(provider.id.value, "No models returned")
                null
            } else {
                setModelFetchStatus(provider.id.value, "Fetched ${fetched.size} models")
                provider.copy(
                    models = fetched.mapIndexed { index, (id, label) ->
                        ModelConfig(
                            modelId = id,
                            displayName = label?.takeIf { it.isNotBlank() && it != id },
                            isActive = index == 0,
                        )
                    },
                    updatedAt = System.currentTimeMillis(),
                )
            }
        } catch (e: Exception) {
            setModelFetchStatus(provider.id.value, "Model fetch failed: ${e.message ?: "unknown error"}")
            null
        }
    }

    private fun setModelFetchStatus(providerId: String, status: String) {
        _uiState.value = _uiState.value.copy(
            modelFetchStatus = _uiState.value.modelFetchStatus + (providerId to status),
        )
    }

    private suspend fun refreshProvidersState() {
        _uiState.value = _uiState.value.copy(
            providers = providerRepository.getAllProviders(),
            activeProviderId = providerRepository.getActiveProvider()?.id,
        )
    }
}
