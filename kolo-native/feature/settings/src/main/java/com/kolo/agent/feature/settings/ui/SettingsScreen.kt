package com.kolo.agent.feature.settings.ui

import androidx.compose.animation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kolo.agent.core.model.*
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.providers.local.LocalModelManager
import com.kolo.agent.feature.settings.*
import java.net.MalformedURLException
import java.io.File
import java.net.URL
import java.util.UUID
import androidx.compose.ui.platform.LocalContext
import android.content.Intent
import android.provider.Settings
import org.json.JSONException
import org.json.JSONTokener
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    state: SettingsUiState,
    onAddProvider: (ProviderConfig, String) -> Unit,
    onUpdateProvider: (ProviderConfig, String?) -> Unit,
    onDeleteProvider: (ProviderId) -> Unit,
    onSetActiveProvider: (ProviderId) -> Unit,
    onSetProviderActiveModel: (ProviderId, String) -> Unit,
    onSetProviderModelPath: (ProviderId, String) -> Unit,
    onRefreshProviderModels: (ProviderId) -> Unit,
    onSetToolPermission: (String, ToolPermissionMode) -> Unit,
    onAddMemory: (String, String) -> Unit,
    onDeleteMemory: (String) -> Unit,
    onSetCustomInstructions: (String) -> Unit,
    onSaveCustomTool: (CustomToolDef) -> Unit,
    onDeleteCustomTool: (String) -> Unit,
    onSaveSkill: (Skill) -> Unit,
    onDeleteSkill: (String) -> Unit,
    onSetSkillEnabled: (String, Boolean) -> Unit,
    onSetTheme: (AppThemeMode) -> Unit = {},
    onSetLocalLlamaGpuMode: (Boolean) -> Unit = {},
    onSetShowTokenUsage: (Boolean) -> Unit = {},
    onNavigateLocalModels: () -> Unit = {},
    onNavigateBack: () -> Unit,
) {
    var selectedSection by remember { mutableStateOf<SettingsSection?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = selectedSection?.title ?: "Settings",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (selectedSection != null) selectedSection = null
                        else onNavigateBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { paddingValues ->
        AnimatedContent(
            targetState = selectedSection,
            transitionSpec = {
                slideInVertically() + fadeIn() togetherWith slideOutVertically() + fadeOut()
            },
            label = "settings-section",
            modifier = Modifier.padding(paddingValues),
        ) { section ->
            when (section) {
                SettingsSection.Providers -> ProvidersSection(
                    providers = state.providers,
                    activeProviderId = state.activeProviderId,
                    bridgeStatus = state.bridgeStatus,
                    activeModelPath = state.localLlamaModelPath,
                    localGpuLayers = state.localLlamaGpuLayers,
                    modelFetchStatus = state.modelFetchStatus,
                    onAddProvider = onAddProvider,
                    onUpdateProvider = onUpdateProvider,
                    onDeleteProvider = onDeleteProvider,
                    onSetActiveProvider = onSetActiveProvider,
                    onSetProviderActiveModel = onSetProviderActiveModel,
                    onSetProviderModelPath = onSetProviderModelPath,
                    onRefreshProviderModels = onRefreshProviderModels,
                    onSetLocalLlamaGpuMode = onSetLocalLlamaGpuMode,
                )
                SettingsSection.Tools -> ToolsSection(
                    toolPermissions = state.toolPermissions,
                    onSetPermission = onSetToolPermission,
                )
                SettingsSection.CustomTools -> CustomToolsSection(
                    tools = state.customTools,
                    onSave = onSaveCustomTool,
                    onDelete = onDeleteCustomTool,
                    onEdit = onSaveCustomTool,
                )
                SettingsSection.Skills -> SkillsSection(
                    skills = state.skills,
                    onSave = onSaveSkill,
                    onDelete = onDeleteSkill,
                    onSetEnabled = onSetSkillEnabled,
                    onEdit = onSaveSkill,
                )
                SettingsSection.Memory -> MemorySection(
                    memories = state.memories,
                    onAdd = onAddMemory,
                    onDelete = onDeleteMemory,
                )
                SettingsSection.Instructions -> InstructionsSection(
                    customInstructions = state.customInstructions,
                    onSave = onSetCustomInstructions,
                )
                SettingsSection.PhoneControl -> PhoneControlSection()
                SettingsSection.Appearance -> AppearanceSection(
                    themeMode = state.themeMode,
                    onSetTheme = onSetTheme,
                    showTokenUsage = state.showTokenUsage,
                    onSetShowTokenUsage = onSetShowTokenUsage,
                )
                SettingsSection.About -> AboutSection(state.bridgeStatus)
                null -> SettingsHome(onSectionSelected = { selectedSection = it }, onNavigateLocalModels = onNavigateLocalModels)
            }
        }
    }
}

// ──── Home ────

@Composable
private fun SettingsHome(onSectionSelected: (SettingsSection) -> Unit, onNavigateLocalModels: () -> Unit = {}) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(0.dp),
        contentPadding = PaddingValues(vertical = 4.dp),
    ) {
        item {
            SectionHeader("Providers & Models")
            SettingsItem(icon = Icons.Filled.Cloud, title = "Providers", subtitle = "API providers and models", onClick = { onSectionSelected(SettingsSection.Providers) })
            SettingsItem(icon = Icons.Filled.Memory, title = "Local Models", subtitle = "Import & manage GGUF models", onClick = onNavigateLocalModels)
        }
        item {
            SectionHeader("Agent")
            SettingsItem(icon = Icons.Filled.Build, title = "Tool Permissions", subtitle = "Which tools the agent can use", onClick = { onSectionSelected(SettingsSection.Tools) })
            SettingsItem(icon = Icons.Filled.Extension, title = "Custom Tools", subtitle = "Author reusable agent tools", onClick = { onSectionSelected(SettingsSection.CustomTools) })
            SettingsItem(icon = Icons.Filled.AutoStories, title = "Skills", subtitle = "Reusable playbooks in prompts", onClick = { onSectionSelected(SettingsSection.Skills) })
            SettingsItem(icon = Icons.Filled.Psychology, title = "Memory", subtitle = "Agent memories", onClick = { onSectionSelected(SettingsSection.Memory) })
            SettingsItem(icon = Icons.Filled.Rule, title = "Instructions", subtitle = "Custom system guidance", onClick = { onSectionSelected(SettingsSection.Instructions) })
        }
        item {
            SectionHeader("App")
            SettingsItem(icon = Icons.Filled.PhoneAndroid, title = "Phone Control", subtitle = "Accessibility service & overlay", onClick = { onSectionSelected(SettingsSection.PhoneControl) })
            SettingsItem(icon = Icons.Filled.Palette, title = "Appearance", subtitle = "Theme, colors", onClick = { onSectionSelected(SettingsSection.Appearance) })
            SettingsItem(icon = Icons.Filled.Info, title = "About", subtitle = "Version, diagnostics", onClick = { onSectionSelected(SettingsSection.About) })
        }
    }
}

@Composable private fun SectionHeader(text: String) {
    Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 12.dp, top = 10.dp, bottom = 4.dp))
}

@Composable
private fun SettingsItem(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = MaterialTheme.shapes.small, modifier = Modifier.fillMaxWidth()) {
        Row(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f), modifier = Modifier.size(18.dp))
        }
    }
}

// ──── Providers ────

@Composable
private fun ProvidersSection(
    providers: List<ProviderConfig>,
    activeProviderId: ProviderId?,
    bridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown,
    activeModelPath: String = "",
    localGpuLayers: Int = 0,
    modelFetchStatus: Map<String, String> = emptyMap(),
    onAddProvider: (ProviderConfig, String) -> Unit,
    onUpdateProvider: (ProviderConfig, String?) -> Unit,
    onDeleteProvider: (ProviderId) -> Unit,
    onSetActiveProvider: (ProviderId) -> Unit,
    onSetProviderActiveModel: (ProviderId, String) -> Unit,
    onSetProviderModelPath: (ProviderId, String) -> Unit,
    onRefreshProviderModels: (ProviderId) -> Unit,
    onSetLocalLlamaGpuMode: (Boolean) -> Unit,
) {
    var showAddDialog by remember { mutableStateOf(false) }
    var expandedProvider by remember { mutableStateOf<ProviderId?>(null) }
    var pendingDeleteProvider by remember { mutableStateOf<ProviderConfig?>(null) }
    val existingProviderNames = remember(providers) { providers.map { it.name.lowercase() }.toSet() }

    LazyColumn(modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp), contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            FilledTonalButton(onClick = { showAddDialog = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Add Provider", style = MaterialTheme.typography.bodyMedium)
            }
        }
        items(providers) { provider ->
            ProviderCard(
                provider = provider,
                isActive = provider.id == activeProviderId,
                isExpanded = provider.id == expandedProvider,
                bridgeStatus = bridgeStatus,
                activeModelPath = activeModelPath,
                localGpuLayers = localGpuLayers,
                modelFetchStatus = modelFetchStatus[provider.id.value],
                onToggleExpand = { expandedProvider = if (expandedProvider == provider.id) null else provider.id },
                onUpdateProvider = onUpdateProvider,
                onSetActive = { onSetActiveProvider(provider.id) },
                onSetActiveModel = { modelId -> onSetProviderActiveModel(provider.id, modelId) },
                onDelete = { pendingDeleteProvider = provider },
                onSetModelPath = { onSetProviderModelPath(provider.id, it) },
                onRefreshModels = { onRefreshProviderModels(provider.id) },
                onSetLocalLlamaGpuMode = onSetLocalLlamaGpuMode,
                existingProviderNames = existingProviderNames,
            )
        }
    }
    pendingDeleteProvider?.let { provider ->
        AlertDialog(
            onDismissRequest = { pendingDeleteProvider = null },
            title = { Text("Delete provider?") },
            text = {
                Text("Delete \"${provider.name}\" permanently? This action will remove the provider and all of its model metadata.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDeleteProvider(provider.id)
                        pendingDeleteProvider = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { pendingDeleteProvider = null }) { Text("Cancel") } },
        )
    }
    if (showAddDialog) {
        AddProviderDialog(
            bridgeStatus = bridgeStatus,
            existingProviderNames = existingProviderNames,
            onDismiss = { showAddDialog = false },
            onConfirm = { config, apiKey ->
                onAddProvider(config, apiKey)
                showAddDialog = false
            },
        )
    }
}

@Composable
private fun ProviderCard(
    provider: ProviderConfig,
    isActive: Boolean,
    isExpanded: Boolean,
    bridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown,
    activeModelPath: String = "",
    localGpuLayers: Int = 0,
    modelFetchStatus: String? = null,
    onToggleExpand: () -> Unit,
    onUpdateProvider: (ProviderConfig, String?) -> Unit,
    onSetActive: () -> Unit,
    onSetActiveModel: (String) -> Unit,
    onDelete: () -> Unit,
    onSetModelPath: (String) -> Unit,
    onRefreshModels: () -> Unit,
    onSetLocalLlamaGpuMode: (Boolean) -> Unit,
    existingProviderNames: Set<String> = emptySet(),
) {
    var modelPathDraft by remember(provider.id, provider.modelPath) { mutableStateOf(provider.modelPath.orEmpty()) }
    var modelSearch by remember(provider.id) { mutableStateOf("") }
    val trimmedModelPath = modelPathDraft.trim()
    val pathError = if (trimmedModelPath.isBlank()) null else {
        val candidate = File(trimmedModelPath)
        when {
            !candidate.exists() -> "Selected file does not exist."
            !candidate.isFile -> "Path must point to a file."
            !candidate.name.lowercase().endsWith(".gguf") -> "Path should point to a .gguf file."
            else -> null
        }
    }
    val filteredModels = provider.models.filter {
        modelSearch.isBlank() || it.label.contains(modelSearch, ignoreCase = true) || it.modelId.contains(modelSearch, ignoreCase = true)
    }
    var showEditDialog by remember { mutableStateOf(false) }
    Card(onClick = onToggleExpand, colors = CardDefaults.cardColors(containerColor = if (isActive) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface), shape = MaterialTheme.shapes.small) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(imageVector = when (provider.kind) { ProviderKind.localLlama -> Icons.Filled.Memory; ProviderKind.openaiCompat -> Icons.Filled.Cloud }, contentDescription = null, tint = if (isActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(provider.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    if (provider.isLocal) {
                        val displayPath = provider.modelPath ?: activeModelPath.ifBlank { null }
                        Text(displayPath?.substringAfterLast("/") ?: "No model selected", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    } else {
                        Text(provider.baseUrl, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (isActive) { Badge { Text("Active") } }
            }
            AnimatedVisibility(visible = isExpanded) {
                Column(modifier = Modifier.padding(top = 8.dp)) {
                    provider.activeModel?.let { model -> Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Model", style = MaterialTheme.typography.labelSmall); Text(model.label, style = MaterialTheme.typography.bodySmall) } }
                    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Type", style = MaterialTheme.typography.labelSmall); Text(when (provider.kind) { ProviderKind.openaiCompat -> "OpenAI-Compatible"; ProviderKind.localLlama -> "Local llama.cpp" }, style = MaterialTheme.typography.bodySmall) }
                    if (provider.isLocal) {
                        Spacer(Modifier.height(8.dp))
                        Text("Runtime", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(
                                selected = localGpuLayers == 0,
                                onClick = { onSetLocalLlamaGpuMode(false) },
                                leadingIcon = { Icon(Icons.Filled.Memory, contentDescription = null, modifier = Modifier.size(16.dp)) },
                                label = { Text("CPU") },
                            )
                            FilterChip(
                                selected = localGpuLayers > 0,
                                onClick = { onSetLocalLlamaGpuMode(true) },
                                leadingIcon = { Icon(Icons.Filled.Speed, contentDescription = null, modifier = Modifier.size(16.dp)) },
                                label = { Text("GPU") },
                            )
                        }
                        Text(
                            if (localGpuLayers > 0) "GPU uses Vulkan full-layer offload when the driver supports it. Switch back to CPU if a model is slow or unstable."
                            else "CPU keeps llama.cpp fully on processor cores.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(8.dp))
                        // Show active inherited model or manual override status
                        if (!provider.modelPath.isNullOrBlank()) {
                            // Manual path override
                            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.3f))) {
                                Row(modifier = Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.Edit, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(14.dp))
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text("Manual path overrides active imported model", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        } else if (activeModelPath.isNotBlank()) {
                            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.2f))) {
                                Row(modifier = Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(14.dp))
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text("Using active model from Local Models", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        } else {
                            // No active model and no override - clear warning
                            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.2f))) {
                                Row(modifier = Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(14.dp))
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text("No active model set. Import a GGUF model in Local Models first.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onErrorContainer)
                                }
                            }
                        }
                        Text("Manage models in Settings > Local Models.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(4.dp))
                        Text("Advanced: manual path override", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                        OutlinedTextField(
                            value = modelPathDraft,
                            onValueChange = { modelPathDraft = it },
                            label = { Text("Manual GGUF path") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                            isError = pathError != null,
                            supportingText = pathError?.let { { Text(it) } },
                        )
                        Spacer(Modifier.height(6.dp))
                        OutlinedButton(
                            onClick = { onSetModelPath(modelPathDraft) },
                            enabled = pathError == null && trimmedModelPath != provider.modelPath.orEmpty(),
                            contentPadding = PaddingValues(horizontal = 12.dp),
                        ) { Text("Save Path", style = MaterialTheme.typography.labelSmall) }
                    } else {
                        Spacer(Modifier.height(8.dp))
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("${provider.models.size} models", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                modelFetchStatus?.let {
                                    Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                                }
                            }
                            OutlinedButton(
                                onClick = onRefreshModels,
                                contentPadding = PaddingValues(horizontal = 12.dp),
                            ) {
                                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(14.dp))
                                Spacer(Modifier.width(4.dp))
                                Text("Fetch Models", style = MaterialTheme.typography.labelSmall)
                            }
                        }
                        if (provider.models.isNotEmpty()) {
                            Spacer(Modifier.height(8.dp))
                            Text("Model", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            OutlinedTextField(
                                value = modelSearch,
                                onValueChange = { modelSearch = it },
                                label = { Text("Search models") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Spacer(Modifier.height(2.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                if (filteredModels.isEmpty()) {
                                    Text(
                                        if (modelSearch.isBlank()) "No models available" else "No models match \"$modelSearch\"",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                } else {
                                    filteredModels.forEach { model ->
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            verticalAlignment = Alignment.CenterVertically,
                                        ) {
                                            RadioButton(
                                                selected = model.modelId == provider.activeModel?.modelId,
                                                onClick = { onSetActiveModel(model.modelId) },
                                            )
                                            Text(
                                                model.label,
                                                style = MaterialTheme.typography.bodySmall,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.weight(1f),
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(6.dp)) {
                        if (!isActive) { OutlinedButton(onClick = onSetActive, contentPadding = PaddingValues(horizontal = 12.dp)) { Text("Set Active", style = MaterialTheme.typography.labelSmall) } }
                        OutlinedButton(onClick = { showEditDialog = true }, contentPadding = PaddingValues(horizontal = 12.dp)) { Text("Edit", style = MaterialTheme.typography.labelSmall) }
                        FilledTonalButton(onClick = onDelete, colors = ButtonDefaults.filledTonalButtonColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer), contentPadding = PaddingValues(horizontal = 12.dp)) { Text("Delete", style = MaterialTheme.typography.labelSmall) }
                    }
                }
            }
        }
    }
    if (showEditDialog) {
        ProviderDetailDialog(
            provider = provider,
            existingProviderNames = existingProviderNames - provider.name.lowercase(),
            onDismiss = { showEditDialog = false },
            onSave = { updated, apiKey ->
                onUpdateProvider(updated, apiKey)
                showEditDialog = false
            },
        )
    }
}

@Composable
private fun AddProviderDialog(
    bridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown,
    existingProviderNames: Set<String> = emptySet(),
    onDismiss: () -> Unit,
    onConfirm: (ProviderConfig, String) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var baseUrl by remember { mutableStateOf("") }
    var apiKey by remember { mutableStateOf("") }
    var modelPath by remember { mutableStateOf("") }
    var providerKind by remember { mutableStateOf(ProviderKind.openaiCompat) }
    var selectedPreset by remember { mutableStateOf(-1) }
    val presets = remember { ProviderPresets.defaults }
    val normalizedBaseUrl = normalizeBaseUrl(baseUrl, fallback = null)
    val effectiveName = name.ifBlank { if (providerKind == ProviderKind.localLlama) "Local llama.cpp" else "" }.trim()
    val nameError = when {
        effectiveName.isBlank() -> "Provider name is required."
        existingProviderNames.contains(effectiveName.lowercase()) -> "A provider with this name already exists."
        else -> null
    }
    val baseUrlError = when {
        providerKind == ProviderKind.localLlama -> null
        normalizedBaseUrl == null && baseUrl.isNotBlank() -> "Use a valid URL (e.g. https://api.openai.com/v1)."
        baseUrl.isBlank() && selectedPreset < 0 -> "Select a preset or enter a base URL."
        else -> null
    }
    val canSave = when {
        providerKind == ProviderKind.localLlama -> nameError == null
        else -> nameError == null && baseUrlError == null
    }

    AlertDialog(onDismissRequest = onDismiss, title = { Text("Add Provider") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                FilterChip(selected = providerKind == ProviderKind.openaiCompat, onClick = { providerKind = ProviderKind.openaiCompat }, label = { Text("Remote API") })
                FilterChip(selected = providerKind == ProviderKind.localLlama, onClick = {
                    providerKind = ProviderKind.localLlama
                    name = name.ifBlank { "Local llama.cpp" }
                    baseUrl = "llama.cpp://local"
                }, label = { Text("Local GGUF") })
            }
            Text("Quick Setup", style = MaterialTheme.typography.labelMedium)
            if (providerKind == ProviderKind.openaiCompat) {
                LazyColumn(modifier = Modifier.heightIn(max = 100.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    items(presets) { preset ->
                        val index = presets.indexOf(preset)
                        FilterChip(
                            selected = index == selectedPreset,
                            onClick = {
                                selectedPreset = index
                                name = preset.name
                                baseUrl = preset.baseUrl
                            },
                            label = { Text(preset.name, style = MaterialTheme.typography.bodySmall) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name") },
                singleLine = true,
                isError = nameError != null,
                supportingText = nameError?.let { { Text(it) } },
                modifier = Modifier.fillMaxWidth(),
            )
            if (providerKind == ProviderKind.localLlama) {
                Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = if (bridgeStatus == LocalModelManager.BridgeStatus.Available) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f) else MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f))) {
                    Row(modifier = Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (bridgeStatus == LocalModelManager.BridgeStatus.Available) Icons.Filled.CheckCircle else Icons.Filled.Warning, contentDescription = null, tint = if (bridgeStatus == LocalModelManager.BridgeStatus.Available) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(if (bridgeStatus == LocalModelManager.BridgeStatus.Available) "llama.cpp runtime available" else "llama.cpp runtime NOT available", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Spacer(Modifier.height(4.dp))
                Text("Import GGUF models via Settings \u2192 Local Models, or enter path manually:", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(value = modelPath, onValueChange = { modelPath = it }, label = { Text("GGUF model path (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
            } else {
                OutlinedTextField(
                    value = baseUrl,
                    onValueChange = { baseUrl = it },
                    label = { Text("Base URL") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    isError = baseUrlError != null,
                    supportingText = baseUrlError?.let { { Text(it) } },
                )
                OutlinedTextField(value = apiKey, onValueChange = { apiKey = it }, label = { Text("API Key") }, singleLine = true, modifier = Modifier.fillMaxWidth(), visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
            }
        }
    }, confirmButton = {
        TextButton(
            onClick = {
                val config = if (providerKind == ProviderKind.localLlama) {
                    ProviderConfig(
                        name = effectiveName,
                        baseUrl = "llama.cpp://local",
                        isActive = true,
                        kind = ProviderKind.localLlama,
                        modelPath = modelPath.trim().ifBlank { null },
                        models = listOf(ModelConfig(modelId = "local-gguf", displayName = "Local GGUF", maxTokens = 1024, contextWindow = 4096, isActive = true)),
                    )
                } else {
                    val preset = presets.getOrNull(selectedPreset)
                    val cleanBaseUrl = normalizedBaseUrl ?: preset?.baseUrl ?: "https://api.openai.com/v1"
                    preset?.copy(
                        name = effectiveName.ifBlank { preset.name },
                        baseUrl = cleanBaseUrl,
                        modelsEndpoint = if (cleanBaseUrl == preset.baseUrl.trimEnd('/')) preset.modelsEndpoint else "$cleanBaseUrl/models",
                        isActive = true,
                        updatedAt = System.currentTimeMillis(),
                    ) ?: ProviderConfig(
                        name = effectiveName.ifBlank { "Custom Provider" },
                        baseUrl = cleanBaseUrl,
                        modelsEndpoint = "$cleanBaseUrl/models",
                        isActive = true,
                        kind = ProviderKind.openaiCompat,
                    )
                }
                onConfirm(config, apiKey)
            },
            enabled = canSave,
        ) {
            Text("Add")
        }
    }, dismissButton = {
        TextButton(onClick = onDismiss) { Text("Cancel") }
    })
}

@Composable
private fun ProviderDetailDialog(
    provider: ProviderConfig,
    existingProviderNames: Set<String> = emptySet(),
    onDismiss: () -> Unit,
    onSave: (ProviderConfig, String?) -> Unit,
) {
    var name by remember(provider.id) { mutableStateOf(provider.name) }
    var baseUrl by remember(provider.id) { mutableStateOf(provider.baseUrl) }
    var modelsEndpoint by remember(provider.id) { mutableStateOf(provider.modelsEndpoint.orEmpty()) }
    var apiKey by remember(provider.id) { mutableStateOf("") }
    var headers by remember(provider.id) {
        mutableStateOf(provider.customHeaders.entries.joinToString("\n") { "${it.key}: ${it.value}" })
    }
    val normalizeName = name.ifBlank { provider.name }.trim()
    val normalizedBaseUrl = normalizeBaseUrl(baseUrl, fallback = provider.baseUrl)
    val normalizedModelsEndpoint = normalizeBaseUrl(
        modelsEndpoint,
        fallback = if (normalizedBaseUrl != null) "${normalizedBaseUrl}/models" else provider.modelsEndpoint,
        allowRelative = normalizedBaseUrl != null,
    )
    val baseUrlError = if (provider.isLocal) {
        null
    } else if (normalizedBaseUrl == null) {
        "Enter a valid base URL (for example, https://api.openai.com/v1)."
    } else {
        null
    }
    val modelsEndpointError = if (provider.isLocal) {
        null
    } else if (modelsEndpoint.isNotBlank() && normalizedModelsEndpoint == null) {
        "Enter a valid models endpoint URL."
    } else {
        null
    }
    val headerValidation = parseHeaderLinesWithValidation(headers)
    val hasHeaderErrors = headerValidation.errors.isNotEmpty()
    val hasDuplicateName = existingProviderNames.contains(normalizeName.lowercase()) && normalizeName.lowercase() != provider.name.lowercase()
    val nameError = when {
        normalizeName.isBlank() -> "Provider name is required."
        hasDuplicateName -> "A provider with this name already exists."
        else -> null
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Provider Details") },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.heightIn(max = 440.dp)) {
                item {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = { Text("Name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        isError = nameError != null,
                        supportingText = nameError?.let { { Text(it) } },
                    )
                }
                item {
                    OutlinedTextField(
                        value = baseUrl,
                        onValueChange = { baseUrl = it },
                        label = { Text("Base URL") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                        isError = baseUrlError != null,
                        supportingText = baseUrlError?.let { { Text(it) } },
                    )
                }
                if (!provider.isLocal) {
                    item {
                        OutlinedTextField(
                            value = modelsEndpoint,
                            onValueChange = { modelsEndpoint = it },
                            label = { Text("Models endpoint") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                            isError = modelsEndpointError != null,
                            supportingText = modelsEndpointError?.let { { Text(it) } },
                        )
                    }
                    item { OutlinedTextField(value = apiKey, onValueChange = { apiKey = it }, label = { Text("API key (leave blank to keep)") }, singleLine = true, modifier = Modifier.fillMaxWidth(), visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password)) }
                    item {
                        OutlinedTextField(
                            value = headers,
                            onValueChange = { headers = it },
                            label = { Text("Custom headers") },
                            placeholder = { Text("HTTP-Referer: https://example.com\nX-Title: Kolo") },
                            minLines = 3,
                            maxLines = 6,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    item {
                        if (headerValidation.errors.isNotEmpty()) {
                            Text(
                                "Header issues: ${headerValidation.errors.joinToString() }",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                        } else {
                            Text(
                                "Use each header on a separate line as `Header: Value`.",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        provider.copy(
                            name = name.ifBlank { provider.name },
                            baseUrl = normalizedBaseUrl ?: baseUrl.trim().trimEnd('/'),
                            modelsEndpoint = normalizedModelsEndpoint?.trim()?.ifBlank { null },
                            customHeaders = headerValidation.headers,
                        ),
                        apiKey.trim().ifBlank { null },
                    )
                },
                enabled = nameError == null && baseUrlError == null && modelsEndpointError == null && !hasHeaderErrors,
            ) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

private data class ParsedHeaderLines(
    val headers: Map<String, String>,
    val errors: List<String>,
)

private fun parseHeaderLinesWithValidation(value: String): ParsedHeaderLines {
    val parsed = mutableMapOf<String, String>()
    val errors = mutableListOf<String>()
    val seenHeaderLines = mutableMapOf<String, Int>()

    value.lineSequence().forEachIndexed { index, rawLine ->
        val line = rawLine.trim()
        if (line.isBlank()) return@forEachIndexed
        if (!line.contains(":")) {
            errors += "Line ${index + 1}: missing ':'"
            return@forEachIndexed
        }
        val key = line.substringBefore(":").trim()
        val headerValue = line.substringAfter(":").trim()
        if (key.isBlank()) {
            errors += "Line ${index + 1}: missing header name"
            return@forEachIndexed
        }
        if (headerValue.isBlank()) {
            errors += "Line ${index + 1}: missing value for '$key'"
            return@forEachIndexed
        }
        val keyLower = key.lowercase()
        if (seenHeaderLines.containsKey(keyLower)) {
            val previousLine = seenHeaderLines[keyLower] ?: index
            errors += "Line ${index + 1}: duplicate header '$key' (first seen on line ${previousLine + 1})"
            return@forEachIndexed
        }
        parsed[key] = headerValue
        seenHeaderLines[keyLower] = index
    }

    return ParsedHeaderLines(parsed, errors)
}

private fun normalizeBaseUrl(value: String, fallback: String? = null, allowRelative: Boolean = true): String? {
    val trimmed = value.trim()
    if (trimmed.isBlank()) return fallback?.trimEnd('/')
    if (!allowRelative && !trimmed.contains("://")) return null
    return try {
        val normalized = if (trimmed.contains("://")) trimmed else "https://$trimmed"
        val url = URL(normalized)
        if (url.host.isBlank()) null else normalized.trimEnd('/')
    } catch (_: MalformedURLException) {
        null
    } catch (_: IllegalArgumentException) {
        null
    }
}

// ──── Tools ────

@Composable
private fun ToolsSection(toolPermissions: List<ToolPermissionUi>, onSetPermission: (String, ToolPermissionMode) -> Unit) {
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        item { Text("Configure tool permissions. Safe=auto, Sensitive/Dangerous=ask or block.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Spacer(Modifier.height(10.dp)) }
        val grouped = toolPermissions.groupBy { perm -> when { perm.isDangerous -> "Dangerous — Phone Control"; perm.defaultMode == ToolPermissionMode.alwaysAllow -> "Safe — Auto-approved"; else -> "Sensitive — Network & Memory" } }
        grouped.forEach { (group, perms) ->
            item { SectionHeader(group); Spacer(Modifier.height(2.dp)) }
            items(perms) { perm -> ToolPermissionRow(perm = perm, onSetPermission = onSetPermission) }
        }
    }
}

@Composable
private fun ToolPermissionRow(perm: ToolPermissionUi, onSetPermission: (String, ToolPermissionMode) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(perm.displayName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                if (perm.isDangerous) { Spacer(Modifier.width(3.dp)); Badge(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer) { Text("⚠️", style = MaterialTheme.typography.labelSmall) } }
            }
            Text(when (perm.currentMode) { ToolPermissionMode.alwaysAllow -> "Auto-approved"; ToolPermissionMode.askEveryTime -> "Ask each time"; ToolPermissionMode.neverAllow -> "Blocked" }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        var expanded by remember { mutableStateOf(false) }
        OutlinedButton(onClick = { expanded = true }, contentPadding = PaddingValues(horizontal = 10.dp)) { Text(when (perm.currentMode) { ToolPermissionMode.alwaysAllow -> "✓ Allow"; ToolPermissionMode.askEveryTime -> "? Ask"; ToolPermissionMode.neverAllow -> "✗ Block" }, style = MaterialTheme.typography.labelSmall) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("Always Allow") }, onClick = { onSetPermission(perm.name, ToolPermissionMode.alwaysAllow); expanded = false })
            DropdownMenuItem(text = { Text("Ask Every Time") }, onClick = { onSetPermission(perm.name, ToolPermissionMode.askEveryTime); expanded = false })
            DropdownMenuItem(text = { Text("Never Allow") }, onClick = { onSetPermission(perm.name, ToolPermissionMode.neverAllow); expanded = false })
        }
    }
}

// ---- Custom Tools ----

@Composable
private fun CustomToolsSection(
    tools: List<CustomToolDef>,
    onSave: (CustomToolDef) -> Unit,
    onDelete: (String) -> Unit,
    onEdit: (CustomToolDef) -> Unit,
) {
    var showDialog by remember { mutableStateOf(false) }
    var selectedTool by remember { mutableStateOf<CustomToolDef?>(null) }
    var pendingDeleteTool by remember { mutableStateOf<CustomToolDef?>(null) }
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Column {
                    Text("Custom Tools", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text("${tools.size} saved", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                FilledTonalButton(onClick = {
                    selectedTool = null
                    showDialog = true
                }, contentPadding = PaddingValues(horizontal = 10.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Add", style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        if (tools.isEmpty()) {
            item { Text("No custom tools yet.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        items(tools, key = { it.id.value }) { tool ->
            ListItem(
                headlineContent = { Text(tool.name, fontWeight = FontWeight.SemiBold) },
                supportingContent = { Text("${tool.kind.name} / ${tool.permission.name} - ${tool.description}", maxLines = 2, overflow = TextOverflow.Ellipsis) },
                leadingContent = { Icon(Icons.Filled.Extension, contentDescription = null) },
                trailingContent = {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        IconButton(onClick = {
                            selectedTool = tool
                            showDialog = true
                        }) {
                            Icon(Icons.Filled.Edit, contentDescription = "Edit", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        IconButton(onClick = { pendingDeleteTool = tool }) {
                            Icon(Icons.Filled.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                },
            )
        }
    }
    if (showDialog) {
        CustomToolDialog(
            onDismiss = {
                showDialog = false
                selectedTool = null
            },
            onSave = {
                if (selectedTool != null) onEdit(it) else onSave(it)
                selectedTool = null
                showDialog = false
            },
            initialTool = selectedTool,
        )
    }
    pendingDeleteTool?.let { tool ->
        AlertDialog(
            onDismissRequest = { pendingDeleteTool = null },
            title = { Text("Delete Custom Tool") },
            text = { Text("Delete \"${tool.name}\"? This cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDelete(tool.id.value)
                        pendingDeleteTool = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { pendingDeleteTool = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun CustomToolDialog(
    onDismiss: () -> Unit,
    onSave: (CustomToolDef) -> Unit,
    initialTool: CustomToolDef? = null,
) {
    val parsedSchemaDefault = remember(initialTool?.parameterSchema) {
        initialTool?.parameterSchema?.trim()?.ifBlank { """{"type":"object","properties":{}}""" } ?: """{"type":"object","properties":{"input":{"type":"string"}},"required":["input"]}"""
    }
    var name by remember { mutableStateOf(initialTool?.name.orEmpty()) }
    var description by remember { mutableStateOf(initialTool?.description.orEmpty()) }
    var schema by remember { mutableStateOf(parsedSchemaDefault) }
    var systemPrompt by remember { mutableStateOf(initialTool?.systemPrompt.orEmpty()) }
    var userTemplate by remember { mutableStateOf(if (initialTool?.userMessage.orEmpty().isBlank()) "{{input}}" else initialTool?.userMessage.orEmpty()) }
    var kind by remember { mutableStateOf(initialTool?.kind ?: CustomToolKind.prompt) }
    var steps by remember { mutableStateOf(initialTool?.steps.orEmpty().joinToString("\\n") { step ->
        buildString {
            append(step.toolName)
            step.params.forEach { (key, value) ->
                append(" ").append(key).append("=").append(value)
            }
        }
    }) }
    var permission by remember { mutableStateOf(initialTool?.permission ?: ToolPermission.sensitive) }
    val schemaError = remember(schema) { validateToolSchema(schema) }
    val composedSteps = parseComposedStepLines(steps)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initialTool == null) "Add Custom Tool" else "Edit Custom Tool") },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.heightIn(max = 460.dp)) {
                item { OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Tool name") }, placeholder = { Text("summarize_notes") }, singleLine = true, modifier = Modifier.fillMaxWidth()) }
                item { OutlinedTextField(value = description, onValueChange = { description = it }, label = { Text("Description") }, minLines = 2, modifier = Modifier.fillMaxWidth()) }
                item {
                    OutlinedTextField(
                        value = schema,
                        onValueChange = { schema = it },
                        label = { Text("Parameter JSON schema") },
                        minLines = 3,
                        maxLines = 5,
                        modifier = Modifier.fillMaxWidth(),
                        isError = schemaError != null,
                    )
                }
                item {
                    if (schemaError != null) {
                        Text(schemaError, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        FilterChip(selected = kind == CustomToolKind.prompt, onClick = { kind = CustomToolKind.prompt }, label = { Text("Prompt") })
                        FilterChip(selected = kind == CustomToolKind.composed, onClick = { kind = CustomToolKind.composed }, label = { Text("Composed") })
                    }
                }
                if (kind == CustomToolKind.prompt) {
                    item { OutlinedTextField(value = systemPrompt, onValueChange = { systemPrompt = it }, label = { Text("System prompt") }, minLines = 3, maxLines = 5, modifier = Modifier.fillMaxWidth()) }
                    item { OutlinedTextField(value = userTemplate, onValueChange = { userTemplate = it }, label = { Text("User template") }, minLines = 2, maxLines = 4, modifier = Modifier.fillMaxWidth()) }
                } else {
                    item {
                        OutlinedTextField(
                            value = steps,
                            onValueChange = { steps = it },
                            label = { Text("Steps") },
                            placeholder = { Text("calculator expression={{input}}\nweb_search query={{_previous}}") },
                            minLines = 4,
                            maxLines = 8,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(ToolPermission.safe, ToolPermission.sensitive, ToolPermission.dangerous).forEach { option ->
                            FilterChip(selected = permission == option, onClick = { permission = option }, label = { Text(option.name) })
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        CustomToolDef(
                            id = initialTool?.id ?: CustomToolId(UUID.randomUUID().toString()),
                            name = name.trim(),
                            description = description.trim(),
                            kind = kind,
                            parameterSchema = schema.trim(),
                            systemPrompt = systemPrompt.trim(),
                            userMessage = userTemplate,
                            steps = if (kind == CustomToolKind.composed) composedSteps else emptyList(),
                            permission = permission,
                            createdAt = initialTool?.createdAt ?: System.currentTimeMillis(),
                            updatedAt = System.currentTimeMillis(),
                        )
                    )
                },
                enabled = name.isNotBlank() &&
                    description.isNotBlank() &&
                    (kind == CustomToolKind.composed || systemPrompt.isNotBlank()) &&
                    (kind == CustomToolKind.prompt || composedSteps.isNotEmpty()) &&
                    schemaError == null,
            ) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

private fun parseComposedStepLines(value: String): List<ComposedStep> {
    return value.lineSequence()
        .map { it.trim() }
        .filter { it.isNotBlank() }
        .mapNotNull { line ->
            val pieces = line.split(Regex("""\s+""")).filter { it.isNotBlank() }
            val toolName = pieces.firstOrNull()?.trim().orEmpty()
            if (toolName.isBlank()) return@mapNotNull null
            val params = pieces.drop(1).mapNotNull { token ->
                val index = token.indexOf('=')
                if (index <= 0) null else token.substring(0, index) to token.substring(index + 1)
            }.toMap()
            ComposedStep(toolName = toolName, params = params)
        }
        .toList()
}

private fun validateToolSchema(schema: String): String? {
    val trimmed = schema.trim()
    if (trimmed.isBlank()) return "Schema is required."
    return try {
        val element = JSONTokener(trimmed).nextValue()
        if (element is JSONObject) null else "Schema must be a JSON object."
    } catch (e: JSONException) {
        "Invalid JSON: ${e.message}"
    }
}

// ---- Skills ----

@Composable
private fun SkillsSection(
    skills: List<Skill>,
    onSave: (Skill) -> Unit,
    onDelete: (String) -> Unit,
    onSetEnabled: (String, Boolean) -> Unit,
    onEdit: (Skill) -> Unit,
) {
    var showDialog by remember { mutableStateOf(false) }
    var selectedSkill by remember { mutableStateOf<Skill?>(null) }
    var pendingDeleteSkill by remember { mutableStateOf<Skill?>(null) }
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Column {
                    Text("Skills", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    Text("${skills.count { it.isEnabled }} enabled / ${skills.size} saved", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                FilledTonalButton(onClick = {
                    selectedSkill = null
                    showDialog = true
                }, contentPadding = PaddingValues(horizontal = 10.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Add", style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        if (skills.isEmpty()) {
            item { Text("No skills yet.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        items(skills, key = { it.id.value }) { skill ->
            ListItem(
                headlineContent = { Text(skill.name, fontWeight = FontWeight.SemiBold) },
                supportingContent = { Text(skill.description, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                leadingContent = { Icon(Icons.Filled.AutoStories, contentDescription = null) },
                trailingContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Switch(checked = skill.isEnabled, onCheckedChange = { onSetEnabled(skill.id.value, it) })
                        IconButton(onClick = {
                            selectedSkill = skill
                            showDialog = true
                        }) {
                            Icon(Icons.Filled.Edit, contentDescription = "Edit", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        IconButton(onClick = { pendingDeleteSkill = skill }) {
                            Icon(Icons.Filled.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                },
            )
        }
    }
    if (showDialog) {
        SkillDialog(
            onDismiss = {
                showDialog = false
                selectedSkill = null
            },
            onSave = {
                if (selectedSkill != null) onEdit(it) else onSave(it)
                selectedSkill = null
                showDialog = false
            },
            initialSkill = selectedSkill,
        )
    }
    pendingDeleteSkill?.let { skill ->
        AlertDialog(
            onDismissRequest = { pendingDeleteSkill = null },
            title = { Text("Delete Skill") },
            text = { Text("Delete \"${skill.name}\"? This cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDelete(skill.id.value)
                        pendingDeleteSkill = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { pendingDeleteSkill = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun SkillDialog(
    onDismiss: () -> Unit,
    onSave: (Skill) -> Unit,
    initialSkill: Skill? = null,
) {
    var name by remember { mutableStateOf(initialSkill?.name.orEmpty()) }
    var description by remember { mutableStateOf(initialSkill?.description.orEmpty()) }
    var content by remember { mutableStateOf(initialSkill?.content.orEmpty()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initialSkill == null) "Add Skill" else "Edit Skill") },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.heightIn(max = 420.dp)) {
                item { OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth()) }
                item { OutlinedTextField(value = description, onValueChange = { description = it }, label = { Text("Description") }, minLines = 2, modifier = Modifier.fillMaxWidth()) }
                item { OutlinedTextField(value = content, onValueChange = { content = it }, label = { Text("Instructions") }, minLines = 8, maxLines = 12, modifier = Modifier.fillMaxWidth()) }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onSave(
                        Skill(
                            id = initialSkill?.id ?: SkillId(UUID.randomUUID().toString()),
                            name = name.trim(),
                            description = description.trim(),
                            content = content.trim(),
                            isEnabled = initialSkill?.isEnabled ?: true,
                            isAgentAuthored = initialSkill?.isAgentAuthored ?: false,
                            createdAt = initialSkill?.createdAt ?: System.currentTimeMillis(),
                            updatedAt = System.currentTimeMillis(),
                        ),
                    )
                },
                enabled = name.isNotBlank() && description.isNotBlank() && content.isNotBlank(),
            ) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ──── Memory ────

@Composable
private fun MemorySection(memories: List<Memory>, onAdd: (String, String) -> Unit, onDelete: (String) -> Unit) {
    var showAddDialog by remember { mutableStateOf(false) }
    var addContent by remember { mutableStateOf("") }
    var addKind by remember { mutableStateOf("fact") }
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                Column { Text("Agent Memory", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold); Text("${memories.size} memories", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                FilledTonalButton(onClick = { showAddDialog = true }, contentPadding = PaddingValues(horizontal = 10.dp)) { Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp)); Spacer(Modifier.width(4.dp)); Text("Add", style = MaterialTheme.typography.labelMedium) }
            }
            Spacer(Modifier.height(6.dp))
        }
        if (memories.isEmpty()) {
            item { Column(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.Psychology, contentDescription = null, modifier = Modifier.size(36.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)); Spacer(Modifier.height(4.dp)); Text("No memories yet", style = MaterialTheme.typography.bodyMedium); Text("The agent will remember details from conversations.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
        }
        items(memories, key = { it.id.value }) { memory ->
            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.Top) {
                    Icon(when (memory.kind) { "fact" -> Icons.Filled.Lightbulb; "preference" -> Icons.Filled.Favorite; "instruction" -> Icons.Filled.Rule; else -> Icons.Filled.Memory }, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Column(Modifier.weight(1f)) { Text(memory.kind.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary); Text(memory.content, style = MaterialTheme.typography.bodySmall) }
                    IconButton(onClick = { onDelete(memory.id.value) }, modifier = Modifier.size(20.dp)) { Icon(Icons.Filled.Close, contentDescription = "Delete", modifier = Modifier.size(12.dp), tint = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }
    if (showAddDialog) {
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text("Add Memory") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("fact", "preference", "instruction").forEach { kind ->
                            FilterChip(
                                selected = addKind == kind,
                                onClick = { addKind = kind },
                                label = { Text(kind.replaceFirstChar { it.uppercase() }) },
                            )
                        }
                    }
                    OutlinedTextField(
                        value = addContent,
                        onValueChange = { addContent = it },
                        label = { Text("What to remember?") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                        maxLines = 4,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (addContent.isNotBlank()) {
                            onAdd(addContent, addKind)
                            addContent = ""
                            addKind = "fact"
                        }
                        showAddDialog = false
                    },
                    enabled = addContent.isNotBlank(),
                ) { Text("Remember") }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = false }) { Text("Cancel") }
            },
        )
    }
}

// ──── Instructions ────

@Composable
private fun InstructionsSection(
    customInstructions: String,
    onSave: (String) -> Unit,
) {
    var draft by remember(customInstructions) { mutableStateOf(customInstructions) }
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Text("Custom Instructions", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Text("These instructions are added to every chat turn.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                label = { Text("Instructions") },
                minLines = 6,
                maxLines = 10,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(
                    onClick = { onSave(draft) },
                    enabled = draft.trim() != customInstructions.trim(),
                ) {
                    Text("Save")
                }
                OutlinedButton(
                    onClick = {
                        draft = ""
                        onSave("")
                    },
                    enabled = customInstructions.isNotBlank() || draft.isNotBlank(),
                ) {
                    Text("Clear")
                }
            }
        }
    }
}

// ──── Phone Control ────

@Composable
private fun PhoneControlSection() {
    val context = LocalContext.current
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                Column(Modifier.padding(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.PhoneAndroid, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(8.dp))
                        Text("Phone Control", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text("Required permission:", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                    Text("Android Settings → Accessibility → Kolo AI Agent", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(6.dp))
                    Text("Safety guarantee:", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                    Text("A persistent STOP overlay appears during active sessions. Pressing it blocks all phone-control actions immediately.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    FilledTonalButton(
                        onClick = {
                            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        },
                    ) {
                        Icon(Icons.Filled.Settings, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Open Accessibility Settings")
                    }
                }
            }
        }
        item {
            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.5f))) {
                Column(Modifier.padding(12.dp)) {
                    Text("Session States", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(6.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) { Badge(containerColor = MaterialTheme.colorScheme.outlineVariant) { Text("inactive") }; Spacer(Modifier.width(6.dp)); Text("No control session running", style = MaterialTheme.typography.bodySmall) }
                    Spacer(Modifier.height(3.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) { Badge(containerColor = MaterialTheme.colorScheme.primaryContainer) { Text("active") }; Spacer(Modifier.width(6.dp)); Text("Agent may use phone tools", style = MaterialTheme.typography.bodySmall) }
                    Spacer(Modifier.height(3.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) { Badge(containerColor = MaterialTheme.colorScheme.errorContainer) { Text("stopped") }; Spacer(Modifier.width(6.dp)); Text("All phone tools blocked until restart", style = MaterialTheme.typography.bodySmall) }
                }
            }
        }
    }
}

// ──── Appearance ────

@Composable
private fun AppearanceSection(
    themeMode: AppThemeMode,
    onSetTheme: (AppThemeMode) -> Unit,
    showTokenUsage: Boolean,
    onSetShowTokenUsage: (Boolean) -> Unit,
) {
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            SectionHeader("Theme")
        }
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ThemeOptionButton("System", AppThemeMode.SYSTEM, themeMode, onSetTheme, Modifier.weight(1f))
                ThemeOptionButton("Light", AppThemeMode.LIGHT, themeMode, onSetTheme, Modifier.weight(1f))
                ThemeOptionButton("Dark", AppThemeMode.DARK, themeMode, onSetTheme, Modifier.weight(1f))
            }
        }
        item {
            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) { Column(Modifier.padding(12.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Memory, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Local Model", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold) }; Spacer(Modifier.height(4.dp)); Text("llama.cpp JNI/CMake bridge is built into this build. Import GGUF models via Settings > Local Models to start local inference.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
        }
        item {
            SwitchPreference(
                "Show Token Usage",
                "Token count bar in chat",
                showTokenUsage,
                onSetShowTokenUsage,
            )
        }
    }
}

@Composable
private fun ThemeOptionButton(label: String, mode: AppThemeMode, current: AppThemeMode, onSelect: (AppThemeMode) -> Unit, modifier: Modifier = Modifier) {
    val selected = mode == current
    FilledTonalButton(
        onClick = { onSelect(mode) },
        modifier = modifier,
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
            contentColor = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
        ),
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = when (mode) {
                    AppThemeMode.SYSTEM -> Icons.Filled.BrightnessAuto
                    AppThemeMode.LIGHT -> Icons.Filled.LightMode
                    AppThemeMode.DARK -> Icons.Filled.DarkMode
                },
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.height(2.dp))
            Text(label, style = MaterialTheme.typography.labelSmall, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal)
        }
    }
}

@Composable private fun SwitchPreference(title: String, subtitle: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, enabled: Boolean = true) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text(title, style = MaterialTheme.typography.bodyMedium, color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)); Text(subtitle, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled)
    }
}

// ──── About ────

@Composable
private fun AboutSection(bridgeStatus: LocalModelManager.BridgeStatus = LocalModelManager.BridgeStatus.Unknown) {
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.SmartToy, contentDescription = null, modifier = Modifier.size(36.dp), tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.height(4.dp)); Text("Kolo AI Agent", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold); Text("v1.0.0 (Native)", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
        item { HorizontalDivider() }
        item { Card(shape = MaterialTheme.shapes.small) { Column(Modifier.padding(10.dp)) { Text("What Works", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold); Spacer(Modifier.height(4.dp)); Text("\u2022 OpenAI-compatible streaming chat with tool use", style = MaterialTheme.typography.bodySmall); Text("\u2022 Tool permission gating (allow once / always / deny / block)", style = MaterialTheme.typography.bodySmall); Text("\u2022 Room-backed memory system", style = MaterialTheme.typography.bodySmall); Text("\u2022 Phone control with session safety \u0026 system overlay", style = MaterialTheme.typography.bodySmall); Text("\u2022 Chat list drawer for switching conversations", style = MaterialTheme.typography.bodySmall); Text("\u2022 Web search via DuckDuckGo (no API key needed)", style = MaterialTheme.typography.bodySmall); Text("\u2022 Theme switching (system / light / dark via DataStore)", style = MaterialTheme.typography.bodySmall); Text("\u2022 Local model import \u0026 management via file picker", style = MaterialTheme.typography.bodySmall); Text("\u2022 llama.cpp ${if (bridgeStatus == LocalModelManager.BridgeStatus.Available) "runtime available" else "bridge built but runtime not loaded"}", style = MaterialTheme.typography.bodySmall, color = if (bridgeStatus == LocalModelManager.BridgeStatus.Available) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.tertiary) } } }
        item { Card(shape = MaterialTheme.shapes.small) { Column(Modifier.padding(10.dp)) { Text("Partially Integrated", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.tertiary); Spacer(Modifier.height(4.dp)); Text("\u2022 Pixel screenshot \u2014 working on Android 11+ with active phone-control session; needs device verification", style = MaterialTheme.typography.bodySmall) } } }
        item { Card(shape = MaterialTheme.shapes.small) { Column(Modifier.padding(10.dp)) { Text("Needs Device Verification", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.outline); Spacer(Modifier.height(4.dp)); Text("• Pixel screenshot — code path uses Android 11+ Accessibility screenshot; not verified on device yet", style = MaterialTheme.typography.bodySmall); Text("• System overlay STOP button — overlay layout works but not testable without active session", style = MaterialTheme.typography.bodySmall) } } }
        item { Card(shape = MaterialTheme.shapes.small) { Column(Modifier.padding(10.dp)) { Text("Diagnostics", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold); Spacer(Modifier.height(4.dp)); Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Platform", style = MaterialTheme.typography.bodySmall); Text("Android Native", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }; Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Min SDK", style = MaterialTheme.typography.bodySmall); Text("26", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }; Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("llama.cpp Bridge", style = MaterialTheme.typography.bodySmall); Text(if (bridgeStatus == LocalModelManager.BridgeStatus.Available) "Available" else when (bridgeStatus) { LocalModelManager.BridgeStatus.Unavailable -> "Not Loaded"; else -> "Unknown" }, style = MaterialTheme.typography.bodySmall, color = if (bridgeStatus == LocalModelManager.BridgeStatus.Available) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error) } } } }
    }
}

private enum class SettingsSection(val title: String) {
    Providers("Providers"), Tools("Tool Permissions"), CustomTools("Custom Tools"), Skills("Skills"), Memory("Memory"), Instructions("Instructions"), PhoneControl("Phone Control"), Appearance("Appearance"), About("About"),
}
