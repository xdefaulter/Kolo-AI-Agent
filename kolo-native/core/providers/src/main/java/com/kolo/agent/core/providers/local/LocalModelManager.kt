package com.kolo.agent.core.providers.local

import android.content.Context
import android.net.Uri
import android.os.StatFs
import android.util.Log
import com.kolo.agent.core.settings.AppSettings
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages local GGUF model files in app-private storage.
 *
 * Models are stored under [Context.filesDir]/models/.
 * The active model path is persisted through [AppSettings].
 */
@Singleton
class LocalModelManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val appSettings: AppSettings,
) {
    companion object {
        private const val TAG = "LocalModelManager"
        const val MODELS_DIR = "models"
        private const val MIN_FREE_SPACE_BYTES = 100L * 1024 * 1024 // 100 MB headroom
    }

    private val modelsDir: File
        get() = File(context.filesDir, MODELS_DIR)

    // ──── Bridge availability (checked off main thread, cached) ────

    enum class BridgeStatus { Unknown, Checking, Available, Unavailable }

    private val _bridgeStatus = MutableStateFlow(BridgeStatus.Unknown)
    val bridgeStatus: StateFlow<BridgeStatus> = _bridgeStatus.asStateFlow()

    /** Synchronous cached value for code paths that need it immediately. */
    @Volatile private var bridgeAvailableCached: Boolean? = null

    /** Initialise bridge check on IO dispatcher. Safe to call multiple times. */
    suspend fun checkBridgeAvailability() {
        if (_bridgeStatus.value == BridgeStatus.Available || _bridgeStatus.value == BridgeStatus.Unavailable) return
        _bridgeStatus.value = BridgeStatus.Checking
        val result = withContext(Dispatchers.IO) { LlamaCppBridge.isAvailable() }
        bridgeAvailableCached = result
        _bridgeStatus.value = if (result) BridgeStatus.Available else BridgeStatus.Unavailable
        Log.i(TAG, "Bridge check result: $result")
    }

    /**
     * Synchronous cached check. Returns null if not yet checked.
     * Prefer [bridgeStatus] flow in UI; use this only in non-UI paths
     * (e.g. LlmEngineFactory) where a blocking read is acceptable.
     */
    fun isBridgeAvailableCached(): Boolean? = bridgeAvailableCached

    // ──── Model list ────

    private val _importedModels = MutableStateFlow<List<ImportedModel>>(emptyList())
    val importedModels: StateFlow<List<ImportedModel>> = _importedModels.asStateFlow()

    private val _activeModelPath = MutableStateFlow<String?>(null)
    val activeModelPath: StateFlow<String?> = _activeModelPath.asStateFlow()

    private val _importStatus = MutableStateFlow<ImportStatus>(ImportStatus.Idle)
    val importStatus: StateFlow<ImportStatus> = _importStatus.asStateFlow()

    sealed class ImportStatus {
        data object Idle : ImportStatus()
        data class Importing(val fileName: String, val progress: Float = 0f, val bytesReceived: Long = 0L, val totalBytes: Long = -1L) : ImportStatus()
        data class Success(val model: ImportedModel) : ImportStatus()
        data class Error(val message: String) : ImportStatus()
    }

    init {
        // Ensure models directory exists synchronously
        modelsDir.mkdirs()
    }

    /**
     * Initialise by loading the stored active model path and scanning models.
     * Uses first() to avoid suspending forever on the DataStore flow.
     */
    suspend fun initialize() {
        val storedPath = appSettings.localLlamaModelPath.first()
        _activeModelPath.value = storedPath
        refreshModelList()
        checkBridgeAvailability()
    }

    /**
     * Scan the models directory and update the list.
     */
    fun refreshModelList() {
        _importedModels.value = GgufHelpers.scanModelsDir(modelsDir)
    }

    /**
     * Import a GGUF model from a content URI (e.g., from the system file picker).
     * Accepts any MIME type from the picker but validates extension and magic.
     * Copies the file into app-private storage with collision handling.
     *
     * @return the imported model, or null on failure.
     */
    suspend fun importModel(uri: Uri): ImportedModel? = withContext(Dispatchers.IO) {
        val fileName = resolveFileName(uri) ?: return@withContext run {
            _importStatus.value = ImportStatus.Error("Could not determine file name from URI")
            null
        }

        // Early extension check: reject non-.gguf before copying
        if (!fileName.endsWith(".gguf", ignoreCase = true)) {
            _importStatus.value = ImportStatus.Error(
                "\"$fileName\" is not a .gguf file. Only GGUF model files are supported."
            )
            return@withContext null
        }

        // Resolve destination with collision handling
        val destFile = GgufHelpers.resolveCollision(modelsDir, fileName)

        _importStatus.value = ImportStatus.Importing(fileName, progress = 0f)

        // Check available storage
        val estimatedSize = estimateContentSize(uri)
        if (estimatedSize > 0L) {
            val freeBytes = getAvailableStorageBytes(modelsDir)
            if (freeBytes < estimatedSize + MIN_FREE_SPACE_BYTES) {
                _importStatus.value = ImportStatus.Error(
                    "Not enough storage space. Need ${GgufHelpers.formatSize(estimatedSize)} but only ${GgufHelpers.formatSize(freeBytes)} available."
                )
                return@withContext null
            }
        }

        // Copy file with progress tracking
        try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                destFile.outputStream().buffered().use { output ->
                    val buffer = ByteArray(32 * 1024) // 32 KB buffer
                    var bytesReceived = 0L
                    val totalBytes = estimatedSize
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        bytesReceived += read
                        if (totalBytes > 0L) {
                            val progress = (bytesReceived.toFloat() / totalBytes).coerceIn(0f, 1f)
                            _importStatus.value = ImportStatus.Importing(
                                fileName = fileName,
                                progress = progress,
                                bytesReceived = bytesReceived,
                                totalBytes = totalBytes,
                            )
                        } else {
                            // No content length; report bytes received but no fraction
                            _importStatus.value = ImportStatus.Importing(
                                fileName = fileName,
                                progress = -1f, // indeterminate
                                bytesReceived = bytesReceived,
                                totalBytes = -1L,
                            )
                        }
                    }
                }
            } ?: run {
                _importStatus.value = ImportStatus.Error("Could not open input stream for URI.")
                return@withContext null
            }
        } catch (e: IOException) {
            Log.e(TAG, "Failed to import model", e)
            destFile.deleteSafely()
            _importStatus.value = ImportStatus.Error("Import failed: ${e.message}")
            return@withContext null
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error importing model", e)
            destFile.deleteSafely()
            _importStatus.value = ImportStatus.Error("Import failed: ${e.message}")
            return@withContext null
        }

        // Validate GGUF magic bytes after copy
        val isValid = GgufHelpers.validateGgufMagic(destFile)
        if (!isValid) {
            destFile.deleteSafely()
            _importStatus.value = ImportStatus.Error(
                "\"$fileName\" does not have a valid GGUF header. The file may be corrupted or a different format."
            )
            return@withContext null
        }

        val model = ImportedModel(
            name = destFile.nameWithoutExtension,
            fileName = destFile.name,
            path = destFile.absolutePath,
            sizeBytes = destFile.length(),
            isValidGguf = true,
        )

        refreshModelList()
        _importStatus.value = ImportStatus.Success(model)
        Log.i(TAG, "Imported model: ${destFile.name} (${GgufHelpers.formatSize(model.sizeBytes)})")
        model
    }

    /**
     * Delete an imported model file.
     */
    suspend fun deleteModel(model: ImportedModel): Boolean = withContext(Dispatchers.IO) {
        val file = File(model.path)
        val deleted = file.deleteSafely()
        if (deleted) {
            refreshModelList()
            if (_activeModelPath.value == model.path) {
                val fallback = _importedModels.value
                    .filter { it.path != model.path }
                    .sortedBy { it.name }
                    .firstOrNull()
                setActiveModel(fallback?.path)
            }
            Log.i(TAG, "Deleted model: ${model.fileName}")
        } else {
            Log.w(TAG, "Failed to delete model: ${model.fileName}")
        }
        deleted
    }

    /**
     * Set the active model path. Persists through AppSettings.
     */
    suspend fun setActiveModel(modelPath: String?) {
        appSettings.setLocalLlamaModelPath(modelPath)
        _activeModelPath.value = modelPath
    }

    /**
     * Clear import status back to Idle (e.g. after user dismissed success/error).
     */
    fun clearImportStatus() {
        _importStatus.value = ImportStatus.Idle
    }

    /**
     * Resolve the display name from a content URI.
     */
    private fun resolveFileName(uri: Uri): String? {
        val cursor = context.contentResolver.query(uri, null, null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    return it.getString(nameIndex)
                }
            }
        }
        return uri.lastPathSegment
    }

    /**
     * Estimate content size from the URI's content length column.
     * Returns 0 if unknown.
     */
    private fun estimateContentSize(uri: Uri): Long {
        return try {
            val cursor = context.contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val sizeIndex = it.getColumnIndex(android.provider.OpenableColumns.SIZE)
                    if (sizeIndex >= 0) {
                        val size = it.getLong(sizeIndex)
                        if (size > 0L) return size
                    }
                }
            }
            0L
        } catch (_: Exception) {
            0L
        }
    }

    /**
     * Get available storage bytes at the given directory path.
     */
    private fun getAvailableStorageBytes(dir: File): Long {
        return try {
            val stat = StatFs(dir.absolutePath)
            stat.availableBlocksLong * stat.blockSizeLong
        } catch (_: Exception) {
            Long.MAX_VALUE // If we can't check, assume enough
        }
    }

    fun totalModelsSize(): Long = _importedModels.value.sumOf { it.sizeBytes }

    fun formatSize(bytes: Long): String = GgufHelpers.formatSize(bytes)
}

/**
 * Represents a GGUF model imported into app-private storage.
 */
data class ImportedModel(
    val name: String,
    val fileName: String,
    val path: String,
    val sizeBytes: Long,
    val isValidGguf: Boolean,
) {
    val sizeFormatted: String
        get() = GgufHelpers.formatSize(sizeBytes)
}

/**
 * Safe file delete that logs on failure.
 */
private fun File.deleteSafely(): Boolean {
    return try {
        val deleted = delete()
        if (!deleted) Log.w("LocalModelManager", "Failed to delete file: $absolutePath")
        deleted
    } catch (e: Exception) {
        Log.w("LocalModelManager", "Exception deleting file: $absolutePath", e)
        false
    }
}
