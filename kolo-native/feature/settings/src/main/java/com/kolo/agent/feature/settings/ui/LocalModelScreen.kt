package com.kolo.agent.feature.settings.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kolo.agent.core.providers.local.ImportedModel
import com.kolo.agent.core.providers.local.LocalModelManager
import com.kolo.agent.feature.settings.LocalModelUiState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocalModelScreen(
    state: LocalModelUiState,
    onImportModel: (Uri) -> Unit,
    onDeleteModel: (ImportedModel) -> Unit,
    onSetActiveModel: (ImportedModel?) -> Unit,
    onClearImportStatus: () -> Unit,
    onConfirmDelete: (ImportedModel) -> Unit,
    onDismissDeleteConfirm: () -> Unit,
    onEnsureLocalProvider: () -> Unit,
    onNavigateBack: () -> Unit,
) {
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        uri?.let { onImportModel(it) }
    }

    // Delete confirmation dialog
    state.showDeleteConfirm?.let { model ->
        AlertDialog(
            onDismissRequest = onDismissDeleteConfirm,
            title = { Text("Delete Model?") },
            text = {
                Text("Delete \"${model.fileName}\" (${model.sizeFormatted})? This cannot be undone.${if (model.path == state.activeModelPath) "\n\nThis is your active model - you will need to set a new one." else ""}")
            },
            confirmButton = {
                TextButton(
                    onClick = { onDeleteModel(model); onDismissDeleteConfirm() },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = onDismissDeleteConfirm) { Text("Cancel") }
            },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Local Models", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { filePickerLauncher.launch(arrayOf("application/octet-stream", "*/*")) },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text("Import GGUF") },
            )
        },
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(paddingValues).padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(vertical = 8.dp),
        ) {
            item { BridgeStatusCard(status = state.bridgeStatus) }

            item {
                AnimatedVisibility(
                    visible = state.importStatus !is LocalModelManager.ImportStatus.Idle,
                    enter = expandVertically() + fadeIn(),
                    exit = shrinkVertically() + fadeOut(),
                ) {
                    ImportStatusCard(
                        status = state.importStatus,
                        onDismiss = onClearImportStatus,
                    )
                }
            }

            item {
                val activeModel = state.importedModels.firstOrNull { it.path == state.activeModelPath }
                ActiveModelCard(
                    activeModel = activeModel,
                    activeModelName = state.activeModelName,
                    onClear = { onSetActiveModel(null) },
                )
            }

            // "Use for Local Chat" action when no local provider and there's an active model
            if (!state.hasLocalProvider && state.activeModelPath != null) {
                item {
                    Card(
                        shape = MaterialTheme.shapes.small,
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.PlayCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(10.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text("Ready for local chat", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.primary)
                                Text("Create a Local llama.cpp provider to start chatting with your model.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(modifier = Modifier.width(6.dp))
                            FilledTonalButton(
                                onClick = onEnsureLocalProvider,
                                contentPadding = PaddingValues(horizontal = 10.dp),
                            ) { Text("Set Up", style = MaterialTheme.typography.labelSmall) }
                        }
                    }
                }
            }

            if (state.importedModels.isEmpty()) {
                item { EmptyModelsCard() }
            } else {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Imported Models", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp, bottom = 4.dp))
                        Text(state.totalModelsSize, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                items(state.importedModels, key = { it.path }) { model ->
                    ImportedModelCard(
                        model = model,
                        isActive = model.path == state.activeModelPath,
                        onSetActivate = { onSetActiveModel(model) },
                        onDelete = { onConfirmDelete(model) },
                    )
                }
            }

            item { HelpCard() }
        }
    }
}

@Composable
private fun BridgeStatusCard(status: LocalModelManager.BridgeStatus) {
    val isAvailable = status == LocalModelManager.BridgeStatus.Available
    val isUnavailable = status == LocalModelManager.BridgeStatus.Unavailable
    val isChecking = status == LocalModelManager.BridgeStatus.Checking
    Card(
        shape = MaterialTheme.shapes.small,
        colors = CardDefaults.cardColors(
            containerColor = when {
                isAvailable -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
                isUnavailable -> MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f)
                else -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
            },
        ),
    ) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (isChecking) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            } else {
                Icon(
                    imageVector = when {
                        isAvailable -> Icons.Filled.CheckCircle
                        isUnavailable -> Icons.Filled.Warning
                        else -> Icons.Filled.HelpOutline
                    },
                    contentDescription = null,
                    tint = when {
                        isAvailable -> MaterialTheme.colorScheme.primary
                        isUnavailable -> MaterialTheme.colorScheme.error
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    modifier = Modifier.size(20.dp),
                )
            }
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    when (status) {
                        LocalModelManager.BridgeStatus.Available -> "llama.cpp Runtime Available"
                        LocalModelManager.BridgeStatus.Unavailable -> "llama.cpp Runtime Unavailable"
                        LocalModelManager.BridgeStatus.Checking -> "Checking llama.cpp runtime..."
                        LocalModelManager.BridgeStatus.Unknown -> "llama.cpp Runtime"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    when (status) {
                        LocalModelManager.BridgeStatus.Available -> "Native bridge is loaded and ready for inference."
                        LocalModelManager.BridgeStatus.Unavailable -> "Native library not loaded. Local inference will not work. Reinstall the app."
                        LocalModelManager.BridgeStatus.Checking -> "Checking..."
                        LocalModelManager.BridgeStatus.Unknown -> "Status not yet checked."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ImportStatusCard(status: LocalModelManager.ImportStatus, onDismiss: () -> Unit) {
    Card(shape = MaterialTheme.shapes.small) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            when (status) {
                is LocalModelManager.ImportStatus.Idle -> { /* not visible */ }
                is LocalModelManager.ImportStatus.Importing -> {
                    if (status.progress >= 0f) {
                        LinearProgressIndicator(
                            progress = { status.progress },
                            modifier = Modifier.width(48.dp).height(4.dp),
                        )
                    } else {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    }
                    Spacer(modifier = Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Importing...", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                        Text(
                            buildString {
                                append(status.fileName)
                                if (status.bytesReceived > 0) {
                                    val received = when {
                                        status.bytesReceived >= 1_000_000L -> "%.1f MB".format(status.bytesReceived / 1_000_000.0)
                                        status.bytesReceived >= 1_000L -> "%.1f KB".format(status.bytesReceived / 1_000.0)
                                        else -> "${status.bytesReceived} B"
                                    }
                                    append(" - $received")
                                    if (status.totalBytes > 0) {
                                        val total = when {
                                            status.totalBytes >= 1_000_000_000L -> "%.1f GB".format(status.totalBytes / 1_000_000_000.0)
                                            status.totalBytes >= 1_000_000L -> "%.1f MB".format(status.totalBytes / 1_000_000.0)
                                            else -> "%.1f KB".format(status.totalBytes / 1_000.0)
                                        }
                                        append(" / $total")
                                    }
                                }
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                is LocalModelManager.ImportStatus.Success -> {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Import complete", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.primary)
                        Text("${status.model.fileName} - ${status.model.sizeFormatted}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    IconButton(onClick = onDismiss, modifier = Modifier.size(24.dp)) {
                        Icon(Icons.Filled.Close, contentDescription = "Dismiss", modifier = Modifier.size(14.dp))
                    }
                }
                is LocalModelManager.ImportStatus.Error -> {
                    Icon(Icons.Filled.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Import failed", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.error)
                        Text(status.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    IconButton(onClick = onDismiss, modifier = Modifier.size(24.dp)) {
                        Icon(Icons.Filled.Close, contentDescription = "Dismiss", modifier = Modifier.size(14.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun ActiveModelCard(activeModel: ImportedModel?, activeModelName: String?, onClear: () -> Unit) {
    Card(shape = MaterialTheme.shapes.small) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.PlayCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Active Model", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            }
            Spacer(modifier = Modifier.height(6.dp))
            if (activeModel != null) {
                Text(activeModelName ?: activeModel.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(activeModel.sizeFormatted, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(activeModel.fileName, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(modifier = Modifier.height(6.dp))
                OutlinedButton(onClick = onClear, contentPadding = PaddingValues(horizontal = 12.dp)) {
                    Text("Clear Active Model", style = MaterialTheme.typography.labelSmall)
                }
            } else {
                Text("No active model. Import a GGUF file and set it as active to enable local inference.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ImportedModelCard(
    model: ImportedModel,
    isActive: Boolean,
    onSetActivate: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(
        shape = MaterialTheme.shapes.small,
        colors = CardDefaults.cardColors(
            containerColor = if (isActive) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        ),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (model.isValidGguf) Icons.Filled.Description else Icons.Filled.Warning,
                    contentDescription = null,
                    tint = when {
                        isActive -> MaterialTheme.colorScheme.primary
                        model.isValidGguf -> MaterialTheme.colorScheme.onSurfaceVariant
                        else -> MaterialTheme.colorScheme.error
                    },
                    modifier = Modifier.size(18.dp),
                )
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(model.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        if (isActive) { Spacer(modifier = Modifier.width(6.dp)); Badge { Text("Active") } }
                    }
                    Text(model.sizeFormatted, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (!model.isValidGguf) {
                        Text("Not a valid GGUF file", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
                    }
                }
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(model.fileName, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(modifier = Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (!isActive) {
                    FilledTonalButton(onClick = onSetActivate, contentPadding = PaddingValues(horizontal = 12.dp)) {
                        Text("Set Active", style = MaterialTheme.typography.labelSmall)
                    }
                }
                OutlinedButton(onClick = onDelete, colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error), contentPadding = PaddingValues(horizontal = 12.dp)) {
                    Text("Delete", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

@Composable
private fun EmptyModelsCard() {
    Card(shape = MaterialTheme.shapes.small) {
        Column(modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Filled.Memory, contentDescription = null, modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f))
            Spacer(modifier = Modifier.height(8.dp))
            Text("No models imported yet", style = MaterialTheme.typography.bodyMedium)
            Spacer(modifier = Modifier.height(4.dp))
            Text("Tap \"Import GGUF\" to select a .gguf model file from your device.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 24.dp))
        }
    }
}

@Composable
private fun HelpCard() {
    Card(shape = MaterialTheme.shapes.small, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.HelpOutline, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("How to use local models", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            }
            Spacer(modifier = Modifier.height(6.dp))
            Text("1. Download a quantized GGUF model to your device.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(2.dp))
            Text("2. Tap Import GGUF to copy it into app storage.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(2.dp))
            Text("3. Set an imported model as active.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(2.dp))
            Text("4. Add a Local llama.cpp provider in Providers, or use the Set Up button above.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(2.dp))
            Text("5. Start chatting with local inference!", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(modifier = Modifier.height(8.dp))
            Text("Tip: Small quantized models (Q4_K_M) work best on mobile. Models are stored in app-private storage.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
