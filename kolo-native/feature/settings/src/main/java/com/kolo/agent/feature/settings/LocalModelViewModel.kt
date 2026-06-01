package com.kolo.agent.feature.settings

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kolo.agent.core.providers.local.ImportedModel
import com.kolo.agent.core.providers.local.LocalModelManager
import com.kolo.agent.core.providers.ProviderRepository
import com.kolo.agent.core.model.ProviderKind
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import java.io.File

data class LocalModelUiState(
    val importedModels: List<ImportedModel> = emptyList(),
    val activeModelPath: String? = null,
    val activeModelName: String? = null,
    val manualPathDraft: String = "",
    val manualPathError: String? = null,
    val bridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown,
    val importStatus: LocalModelManager.ImportStatus = LocalModelManager.ImportStatus.Idle,
    val totalModelsSize: String = "",
    val hasLocalProvider: Boolean = false,
    val showDeleteConfirm: ImportedModel? = null,
)

@HiltViewModel
class LocalModelViewModel @Inject constructor(
    private val localModelManager: LocalModelManager,
    private val providerRepository: ProviderRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(LocalModelUiState())
    val uiState: StateFlow<LocalModelUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            localModelManager.initialize()
            // Now all state flows are populated; collect them for UI
            launch { localModelManager.importedModels.collect { models ->
                val activeName = _uiState.value.activeModelPath?.let { path ->
                    models.firstOrNull { it.path == path }?.name
                }
                _uiState.value = _uiState.value.copy(
                    importedModels = models,
                    activeModelName = activeName,
                    totalModelsSize = localModelManager.formatSize(localModelManager.totalModelsSize()),
                )
            } }
            launch { localModelManager.activeModelPath.collect { path ->
                val activeName = _uiState.value.importedModels.firstOrNull { it.path == path }?.name
                val manualPath = path.orEmpty()
                _uiState.value = _uiState.value.copy(
                    activeModelPath = path,
                    activeModelName = activeName,
                    manualPathDraft = if (manualPath.isNotBlank()) manualPath else "",
                    manualPathError = null,
                )
            } }
            launch { localModelManager.bridgeStatus.collect { status ->
                _uiState.value = _uiState.value.copy(bridgeStatus = status)
            } }
            launch { localModelManager.importStatus.collect { status ->
                _uiState.value = _uiState.value.copy(importStatus = status)
            } }
        }
        // Check if there's a local provider
        checkLocalProvider()
    }

    private fun checkLocalProvider() {
        viewModelScope.launch {
            val providers = providerRepository.getAllProviders()
            _uiState.value = _uiState.value.copy(
                hasLocalProvider = providers.any { it.kind == ProviderKind.localLlama }
            )
        }
    }

    fun importModel(uri: Uri) {
        viewModelScope.launch { localModelManager.importModel(uri) }
    }

    fun deleteModel(model: ImportedModel) {
        viewModelScope.launch {
            localModelManager.deleteModel(model)
            checkLocalProvider()
        }
    }

    fun confirmDelete(model: ImportedModel) {
        _uiState.value = _uiState.value.copy(showDeleteConfirm = model)
    }

    fun dismissDeleteConfirm() {
        _uiState.value = _uiState.value.copy(showDeleteConfirm = null)
    }

    fun setActiveModel(model: ImportedModel?) {
        viewModelScope.launch { localModelManager.setActiveModel(model?.path) }
    }

    fun setActiveModelPath(path: String) {
        val trimmed = path.trim()
        if (trimmed.isBlank()) {
            _uiState.value = _uiState.value.copy(manualPathDraft = "", manualPathError = null)
            viewModelScope.launch { localModelManager.setActiveModel(null) }
            return
        }

        val error = when {
            !File(trimmed).exists() -> "Path does not exist"
            !File(trimmed).isFile -> "Path must be a file"
            !trimmed.lowercase().endsWith(".gguf") -> "Path must point to a .gguf file"
            else -> null
        }

        if (error != null) {
            _uiState.value = _uiState.value.copy(manualPathDraft = trimmed, manualPathError = error)
            return
        }

        _uiState.value = _uiState.value.copy(manualPathDraft = trimmed, manualPathError = null)
        viewModelScope.launch { localModelManager.setActiveModel(trimmed) }
    }

    fun updateManualPathDraft(path: String) {
        val trimmed = path.trim()
        val error = if (trimmed.isBlank()) {
            null
        } else {
            when {
                !File(trimmed).exists() -> "Path does not exist"
                !File(trimmed).isFile -> "Path must be a file"
                !trimmed.lowercase().endsWith(".gguf") -> "Path must point to a .gguf file"
                else -> null
            }
        }
        _uiState.value = _uiState.value.copy(manualPathDraft = path, manualPathError = error)
    }

    fun clearManualPathError() {
        _uiState.value = _uiState.value.copy(manualPathError = null)
    }

    fun clearImportStatus() {
        localModelManager.clearImportStatus()
    }

    /** Create a Local llama.cpp provider if none exists. */
    fun ensureLocalProvider() {
        viewModelScope.launch {
            val providers = providerRepository.getAllProviders()
            if (providers.none { it.kind == ProviderKind.localLlama }) {
                val config = com.kolo.agent.core.model.ProviderConfig(
                    name = "Local llama.cpp",
                    baseUrl = "llama.cpp://local",
                    isActive = true,
                    kind = ProviderKind.localLlama,
                    models = listOf(com.kolo.agent.core.model.ModelConfig(
                        modelId = "local-gguf",
                        displayName = "Local GGUF",
                        maxTokens = 1024,
                        contextWindow = 4096,
                        isActive = true,
                    )),
                )
                providerRepository.saveProvider(config, "")
                _uiState.value = _uiState.value.copy(hasLocalProvider = true)
            }
        }
    }
}
