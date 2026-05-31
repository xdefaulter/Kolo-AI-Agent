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
import com.kolo.agent.feature.settings.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    state: SettingsUiState,
    onAddProvider: (ProviderConfig, String) -> Unit,
    onDeleteProvider: (ProviderId) -> Unit,
    onSetActiveProvider: (ProviderId) -> Unit,
    onSetToolPermission: (String, ToolPermissionMode) -> Unit,
    onAddMemory: (String, String) -> Unit,
    onDeleteMemory: (String) -> Unit,
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
                    onAddProvider = onAddProvider,
                    onDeleteProvider = onDeleteProvider,
                    onSetActiveProvider = onSetActiveProvider,
                )
                SettingsSection.Tools -> ToolsSection(
                    toolPermissions = state.toolPermissions,
                    onSetPermission = onSetToolPermission,
                )
                SettingsSection.Memory -> MemorySection(
                    memories = state.memories,
                    onAdd = onAddMemory,
                    onDelete = onDeleteMemory,
                )
                SettingsSection.PhoneControl -> PhoneControlSection()
                SettingsSection.Appearance -> AppearanceSection()
                SettingsSection.About -> AboutSection()
                null -> SettingsHome(onSectionSelected = { selectedSection = it })
            }
        }
    }
}

// ──── Home ────

@Composable
private fun SettingsHome(onSectionSelected: (SettingsSection) -> Unit) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(1.dp),
        contentPadding = PaddingValues(vertical = 8.dp),
    ) {
        item {
            SectionHeader("Providers & Models")
            SettingsItem(icon = Icons.Filled.Cloud, title = "Providers", subtitle = "API providers and models", onClick = { onSectionSelected(SettingsSection.Providers) })
        }
        item {
            SectionHeader("Agent")
            SettingsItem(icon = Icons.Filled.Build, title = "Tool Permissions", subtitle = "Which tools the agent can use", onClick = { onSectionSelected(SettingsSection.Tools) })
            SettingsItem(icon = Icons.Filled.Psychology, title = "Memory", subtitle = "Agent memories", onClick = { onSectionSelected(SettingsSection.Memory) })
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
        Row(modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
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
    onAddProvider: (ProviderConfig, String) -> Unit,
    onDeleteProvider: (ProviderId) -> Unit,
    onSetActiveProvider: (ProviderId) -> Unit,
) {
    var showAddDialog by remember { mutableStateOf(false) }
    var expandedProvider by remember { mutableStateOf<ProviderId?>(null) }

    LazyColumn(modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp), contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            FilledTonalButton(onClick = { showAddDialog = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Add Provider", style = MaterialTheme.typography.bodyMedium)
            }
        }
        items(providers) { provider ->
            ProviderCard(provider = provider, isActive = provider.id == activeProviderId, isExpanded = provider.id == expandedProvider, onToggleExpand = { expandedProvider = if (expandedProvider == provider.id) null else provider.id }, onSetActive = { onSetActiveProvider(provider.id) }, onDelete = { onDeleteProvider(provider.id) })
        }
    }
    if (showAddDialog) { AddProviderDialog(onDismiss = { showAddDialog = false }, onConfirm = { config, apiKey -> onAddProvider(config, apiKey); showAddDialog = false }) }
}

@Composable
private fun ProviderCard(provider: ProviderConfig, isActive: Boolean, isExpanded: Boolean, onToggleExpand: () -> Unit, onSetActive: () -> Unit, onDelete: () -> Unit) {
    Card(onClick = onToggleExpand, colors = CardDefaults.cardColors(containerColor = if (isActive) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface), shape = MaterialTheme.shapes.small) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(imageVector = when (provider.kind) { ProviderKind.localLlama -> Icons.Filled.Memory; ProviderKind.openaiCompat -> Icons.Filled.Cloud }, contentDescription = null, tint = if (isActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(provider.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(provider.baseUrl, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (isActive) { Badge { Text("Active") } }
            }
            AnimatedVisibility(visible = isExpanded) {
                Column(modifier = Modifier.padding(top = 8.dp)) {
                    provider.activeModel?.let { model -> Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Model", style = MaterialTheme.typography.labelSmall); Text(model.label, style = MaterialTheme.typography.bodySmall) } }
                    Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Type", style = MaterialTheme.typography.labelSmall); Text(when (provider.kind) { ProviderKind.openaiCompat -> "OpenAI-Compatible"; ProviderKind.localLlama -> "Local llama.cpp" }, style = MaterialTheme.typography.bodySmall) }
                    Spacer(Modifier.height(6.dp))
                    Row(Modifier.fillMaxWidth(), Arrangement.spacedBy(6.dp)) {
                        if (!isActive) { OutlinedButton(onClick = onSetActive, contentPadding = PaddingValues(horizontal = 12.dp)) { Text("Set Active", style = MaterialTheme.typography.labelSmall) } }
                        FilledTonalButton(onClick = onDelete, colors = ButtonDefaults.filledTonalButtonColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer), contentPadding = PaddingValues(horizontal = 12.dp)) { Text("Delete", style = MaterialTheme.typography.labelSmall) }
                    }
                }
            }
        }
    }
}

@Composable
private fun AddProviderDialog(onDismiss: () -> Unit, onConfirm: (ProviderConfig, String) -> Unit) {
    var name by remember { mutableStateOf("") }
    var baseUrl by remember { mutableStateOf("") }
    var apiKey by remember { mutableStateOf("") }
    var selectedPreset by remember { mutableStateOf(-1) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Add Provider") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Quick Setup", style = MaterialTheme.typography.labelMedium)
            LazyColumn(modifier = Modifier.heightIn(max = 100.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                items(ProviderPresets.defaults) { preset ->
                    FilterChip(selected = ProviderPresets.defaults.indexOf(preset) == selectedPreset, onClick = { selectedPreset = ProviderPresets.defaults.indexOf(preset); name = preset.name; baseUrl = preset.baseUrl }, label = { Text(preset.name, style = MaterialTheme.typography.bodySmall) }, modifier = Modifier.fillMaxWidth())
                }
            }
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(value = baseUrl, onValueChange = { baseUrl = it }, label = { Text("Base URL") }, singleLine = true, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
            OutlinedTextField(value = apiKey, onValueChange = { apiKey = it }, label = { Text("API Key") }, singleLine = true, modifier = Modifier.fillMaxWidth(), visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
        }
    }, confirmButton = { TextButton(onClick = { val config = ProviderConfig(name = name.ifBlank { "Custom Provider" }, baseUrl = baseUrl.ifBlank { "https://api.openai.com/v1" }, isActive = true, kind = ProviderKind.openaiCompat); onConfirm(config, apiKey) }, enabled = name.isNotBlank() && baseUrl.isNotBlank()) { Text("Add") } }, dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
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

// ──── Phone Control ────

@Composable
private fun PhoneControlSection() {
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
private fun AppearanceSection() {
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) { Column(Modifier.padding(12.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Filled.Memory, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Local Model", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold) }; Spacer(Modifier.height(4.dp)); Text("Local LLM via llama.cpp is not yet available.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
        }
        item { SectionHeader("Theme (preview)"); Text("Theme switching saves to DataStore but does not yet affect the running app.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item { Spacer(Modifier.height(8.dp)) }
        item { SwitchPreference("Dynamic Colors", "Material You on Android 12+", true, { }, false); SwitchPreference("Show Token Usage", "Token count bar in chat", true, { }, false) }
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
private fun AboutSection() {
    LazyColumn(modifier = Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Filled.SmartToy, contentDescription = null, modifier = Modifier.size(44.dp), tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.height(6.dp)); Text("Kolo AI Agent", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold); Text("v1.0.0 (Native)", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
        item { HorizontalDivider() }
        item { Card(shape = MaterialTheme.shapes.small) { Column(Modifier.padding(10.dp)) { Text("What Works", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold); Spacer(Modifier.height(4.dp)); Text("• OpenAI-compatible streaming chat with tool use", style = MaterialTheme.typography.bodySmall); Text("• Tool permission gating (allow once / always / deny / block)", style = MaterialTheme.typography.bodySmall); Text("• Room-backed memory system", style = MaterialTheme.typography.bodySmall); Text("• Phone control with session safety & system overlay", style = MaterialTheme.typography.bodySmall) } } }
        item { Card(shape = MaterialTheme.shapes.small) { Column(Modifier.padding(10.dp)) { Text("Not Yet Available", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.error); Spacer(Modifier.height(4.dp)); Text("• Local LLM (llama.cpp) — scaffolding only", style = MaterialTheme.typography.bodySmall); Text("• Web search — placeholder, no API connected", style = MaterialTheme.typography.bodySmall); Text("• Visual screenshot — accessibility tree only, no pixel capture", style = MaterialTheme.typography.bodySmall); Text("• Chat list drawer — not yet implemented", style = MaterialTheme.typography.bodySmall); Text("• Theme switching — DataStore wired, UI not applied", style = MaterialTheme.typography.bodySmall) } } }
        item { Card(shape = MaterialTheme.shapes.small) { Column(Modifier.padding(10.dp)) { Text("Diagnostics", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold); Spacer(Modifier.height(4.dp)); Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Platform", style = MaterialTheme.typography.bodySmall); Text("Android Native", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }; Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) { Text("Min SDK", style = MaterialTheme.typography.bodySmall); Text("26", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) } } } }
    }
}

private enum class SettingsSection(val title: String) {
    Providers("Providers"), Tools("Tool Permissions"), Memory("Memory"), PhoneControl("Phone Control"), Appearance("Appearance"), About("About"),
}