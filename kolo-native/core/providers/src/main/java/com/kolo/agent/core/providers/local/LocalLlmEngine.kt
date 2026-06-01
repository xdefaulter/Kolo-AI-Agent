package com.kolo.agent.core.providers.local

import android.util.Log
import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.ProviderKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Interface for local LLM inference via llama.cpp.
 *
 * This provides a unified API for running models locally on device.
 * The JNI implementation links official llama.cpp sources through CMake.
 */
interface LocalLlmEngine {
    /** Whether a model is currently loaded and ready for inference. */
    val isModelLoaded: Boolean

    /** The path of the currently loaded model, or null. */
    val loadedModelPath: String?

    /**
     * Load a GGUF model from the given path.
     * @param modelPath Absolute path to the .gguf model file.
     * @param contextSize Context window size in tokens.
     * @param threads Number of threads for inference.
     */
    suspend fun loadModel(modelPath: String, contextSize: Int = 4096, threads: Int = 4)

    /** Unload the current model and free memory. */
    suspend fun unloadModel()

    /**
     * Generate text completion in streaming fashion.
     * Yields tokens as they are generated.
     */
    fun completeStream(
        prompt: String,
        maxTokens: Int = 4096,
        temperature: Float = 0.7f,
        topP: Float = 0.95f,
        repeatPenalty: Float = 1.1f,
    ): Flow<String>

    /**
     * Check if a model file exists and appears to be a valid GGUF file.
     */
    fun isValidModel(modelPath: String): Boolean {
        return GgufHelpers.isValidModel(modelPath)
    }

    /**
     * List available GGUF models in known directories.
     */
    fun listAvailableModels(): List<ModelInfo> {
        return LEGACY_MODEL_DIRS.flatMap { dir ->
            val directory = File(dir)
            if (directory.exists() && directory.isDirectory) {
                directory.walkTopDown()
                    .filter { it.extension == "gguf" }
                    .map { file ->
                        ModelInfo(
                            path = file.absolutePath,
                            name = file.nameWithoutExtension,
                            sizeBytes = file.length(),
                        )
                    }
                    .toList()
            } else emptyList()
        }
    }

    /**
     * List available GGUF models including app-private storage.
     */
    fun listAvailableModels(context: android.content.Context): List<ModelInfo> {
        val legacy = listAvailableModels()
        val appDir = appModelsDir(context)
        val appModels = if (appDir.exists() && appDir.isDirectory) {
            appDir.walkTopDown()
                .filter { it.isFile && it.extension == "gguf" }
                .map { file ->
                    ModelInfo(
                        path = file.absolutePath,
                        name = file.nameWithoutExtension,
                        sizeBytes = file.length(),
                    )
                }
                .toList()
        } else emptyList()
        return legacy + appModels
    }

    companion object {
        /** Known model search directories (app-private dir is added at runtime). */
        fun appModelsDir(context: android.content.Context): java.io.File =
            java.io.File(context.filesDir, LocalModelManager.MODELS_DIR)

        val LEGACY_MODEL_DIRS = listOf(
            "/sdcard/llm/models/",
            "/storage/emulated/0/llm/models/",
        )
    }
}

/**
 * Pure (no Android dependency) helper functions for GGUF validation, formatting,
 * and model-list parsing. Testable in plain JUnit without Robolectric.
 */
object GgufHelpers {
    private const val TAG = "GgufHelpers"

    /** The 4-byte GGUF magic: 0x47 0x47 0x55 0x46 ("GGUF"). */
    val GGUF_MAGIC = byteArrayOf(0x47, 0x47, 0x55, 0x46)

    /** Minimum file size to be considered a valid GGUF model (header + metadata). */
    const val MIN_GGUF_FILE_SIZE = 64L

    /**
     * Check if a file at the given path is a valid GGUF model.
     * Pure file-I/O, no Android Context needed.
     */
    fun isValidModel(modelPath: String): Boolean {
        val file = File(modelPath)
        if (!file.exists() || file.length() < MIN_GGUF_FILE_SIZE) return false
        return try {
            file.inputStream().use { stream ->
                val magic = ByteArray(4)
                val read = stream.read(magic)
                read == 4 && magic.contentEquals(GGUF_MAGIC)
            }
        } catch (_: Exception) { false }
    }

    /**
     * Validate that a file has the GGUF magic bytes.
     */
    fun validateGgufMagic(file: File): Boolean {
        if (!file.exists() || file.length() < 8) return false
        return try {
            file.inputStream().buffered().use { stream ->
                val magic = ByteArray(4)
                val read = stream.read(magic)
                read == 4 && magic.contentEquals(GGUF_MAGIC)
            }
        } catch (e: Exception) {
            Log.w(TAG, "GGUF validation failed for ${file.name}: ${e.message}")
            false
        }
    }

    /**
     * Resolve a filename collision by appending "-1", "-2", etc.
     * Returns the first non-existing File in the directory.
     */
    fun resolveCollision(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        if (!candidate.exists()) return candidate
        val baseName = fileName.substringBeforeLast('.')
        val extension = fileName.substringAfterLast('.', "")
        var counter = 1
        while (candidate.exists()) {
            val newName = if (extension.isNotEmpty()) "$baseName-$counter.$extension" else "$baseName-$counter"
            candidate = File(directory, newName)
            counter++
        }
        return candidate
    }

    /**
     * Scan a directory for .gguf files and return model info.
     */
    fun scanModelsDir(dir: File): List<ImportedModel> {
        if (!dir.exists() || !dir.isDirectory) return emptyList()
        return dir.walkTopDown()
            .filter { it.isFile && it.extension == "gguf" }
            .map { file ->
                ImportedModel(
                    name = file.nameWithoutExtension,
                    fileName = file.name,
                    path = file.absolutePath,
                    sizeBytes = file.length(),
                    isValidGguf = validateGgufMagic(file),
                )
            }
            .toList()
    }

    /**
     * Format byte count as human-readable string.
     */
    fun formatSize(bytes: Long): String = when {
        bytes >= 1_000_000_000L -> "%.1f GB".format(bytes / 1_000_000_000.0)
        bytes >= 1_000_000L -> "%.1f MB".format(bytes / 1_000_000.0)
        bytes >= 1_000L -> "%.1f KB".format(bytes / 1_000.0)
        else -> "$bytes B"
    }
}

/**
 * Information about an available model file.
 */
data class ModelInfo(
    val path: String,
    val name: String,
    val sizeBytes: Long,
) {
    val sizeFormatted: String
        get() = GgufHelpers.formatSize(sizeBytes)
}

/**
 * JNI-backed llama.cpp engine.
 *
 * All native calls are dispatched to [Dispatchers.IO].
 * [LlamaCppBridge.isAvailable] is only called inside `withContext(Dispatchers.IO)`
 * to guarantee [System.loadLibrary] never runs on the main thread.
 */
class LlamaCppEngine : LocalLlmEngine {
    companion object {
        private const val TAG = "LlamaCppEngine"
    }

    override var isModelLoaded: Boolean = false
        private set
    override var loadedModelPath: String? = null
        private set
    private var nativeHandle: Long = 0L
    private var loadedContextSize: Int = 0
    private var loadedThreads: Int = 0

    override suspend fun loadModel(modelPath: String, contextSize: Int, threads: Int) {
        if (
            nativeHandle != 0L &&
            isModelLoaded &&
            loadedModelPath == modelPath &&
            loadedContextSize == contextSize &&
            loadedThreads == threads
        ) {
            Log.i(TAG, "Reusing loaded model/context: $modelPath")
            return
        }

        if (nativeHandle != 0L) {
            unloadModel()
        }

        if (!GgufHelpers.isValidModel(modelPath)) {
            Log.e(TAG, "Model file not found or not a valid GGUF: $modelPath")
            throw IllegalArgumentException(
                "Model file not found or not a valid GGUF file: $modelPath"
            )
        }
        // All bridge interaction on IO dispatcher — never main thread
        nativeHandle = withContext(Dispatchers.IO) {
            if (!LlamaCppBridge.isAvailable()) {
                Log.e(TAG, "llama.cpp bridge unavailable at loadModel time")
                throw IllegalStateException(
                    "llama.cpp runtime is unavailable. Reinstall the app to enable local inference."
                )
            }
            LlamaCppBridge.loadModel(modelPath, contextSize, threads)
        }
        if (nativeHandle == 0L) {
            Log.e(TAG, "llama.cpp failed to load model: $modelPath")
            throw IllegalStateException("llama.cpp failed to load model: $modelPath")
        }
        isModelLoaded = true
        loadedModelPath = modelPath
        loadedContextSize = contextSize
        loadedThreads = threads
        Log.i(TAG, "Model loaded: $modelPath")
    }

    override suspend fun unloadModel() {
        if (nativeHandle != 0L) {
            withContext(Dispatchers.IO) {
                // After first check, bridge availability is cached — safe even without re-check
                if (LlamaCppBridge.isAvailable()) {
                    LlamaCppBridge.unloadModel(nativeHandle)
                }
            }
        }
        nativeHandle = 0L
        isModelLoaded = false
        loadedModelPath = null
        loadedContextSize = 0
        loadedThreads = 0
    }

    override fun completeStream(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        repeatPenalty: Float,
    ): Flow<String> = channelFlow {
        if (!isModelLoaded || nativeHandle == 0L) {
            Log.e(TAG, "completeStream called with no model loaded")
            send("[Local LLM not loaded. Import a GGUF model and set it active in Settings > Local Models.]")
            return@channelFlow
        }
        val error = withContext(Dispatchers.IO) {
            if (!LlamaCppBridge.isAvailable()) {
                Log.e(TAG, "Bridge unavailable at completeStream time")
                return@withContext "llama.cpp runtime unavailable"
            }
            LlamaCppBridge.completeStream(
                handle = nativeHandle,
                prompt = prompt,
                maxTokens = maxTokens,
                temperature = temperature,
                topP = topP,
                repeatPenalty = repeatPenalty,
            ) { token ->
                trySend(token).isSuccess
            }
        }
        if (error.isNotBlank() && error != "ok") {
            Log.e(TAG, "Inference error: $error")
            send("[Local LLM inference error: $error]")
        }
    }.flowOn(Dispatchers.IO)
}

/**
 * Fallback used only when the native bridge is genuinely unavailable.
 * Stub exists so the app doesn't crash when a provider config references localLlama.
 *
 * IMPORTANT: The stub should never be used silently when the bridge *might* be
 * available but hasn't been checked yet. [LlmEngineFactory.ensureAndCreate]
 * guarantees the bridge is checked before deciding.
 */
class StubLocalLlmEngine : LocalLlmEngine {
    companion object {
        private const val TAG = "StubLocalLlmEngine"
    }

    override var isModelLoaded: Boolean = false
        private set
    override var loadedModelPath: String? = null
        private set

    override suspend fun loadModel(modelPath: String, contextSize: Int, threads: Int) {
        if (!GgufHelpers.isValidModel(modelPath)) {
            throw IllegalArgumentException("Model file not found or not a valid GGUF file: $modelPath")
        }
        isModelLoaded = true
        loadedModelPath = modelPath
    }

    override suspend fun unloadModel() {
        isModelLoaded = false
        loadedModelPath = null
    }

    override fun completeStream(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        repeatPenalty: Float,
    ): Flow<String> = flow {
        Log.w(TAG, "completeStream on stub engine — bridge unavailable")
        emit("[llama.cpp runtime unavailable. Cannot run local inference. Reinstall the app if this is unexpected.]")
    }.flowOn(Dispatchers.IO)
}

/**
 * Factory to create the appropriate engine based on provider config.
 *
 * Provides two paths:
 * - [create] with [LocalModelManager]: ensures bridge availability is checked
 *   on [Dispatchers.IO] before deciding, so the stub is never used just because
 *   the cache was null.
 * - [create] without manager: synchronous fallback. Must NOT be called on main thread.
 */
object LlmEngineFactory {
    private const val TAG = "LlmEngineFactory"
    private val sharedLlamaEngine = LlamaCppEngine()

    /**
     * Create an engine using a [LocalModelManager], ensuring the bridge
     * has been checked. This is the preferred entry point.
     *
     * - If the cached result is `true`, returns [LlamaCppEngine].
     * - If the cached result is `false`, returns [StubLocalLlmEngine].
     * - If not yet checked (`null`), runs [LocalModelManager.checkBridgeAvailability]
     *   on [Dispatchers.IO] first, then decides.
     *
     * This is a suspend function so it can safely check the bridge off main thread.
     */
    suspend fun ensureAndCreate(config: ProviderConfig, localModelManager: LocalModelManager): LocalLlmEngine {
        if (config.kind != ProviderKind.localLlama) return StubLocalLlmEngine()
        val cached = localModelManager.isBridgeAvailableCached()
        if (cached == true) return sharedLlamaEngine
        if (cached == false) {
            Log.w(TAG, "Bridge cached as unavailable — using StubLocalLlmEngine")
            return StubLocalLlmEngine()
        }
        // Not yet checked: do it now on IO
        Log.i(TAG, "Bridge not yet checked — running checkBridgeAvailability on IO")
        localModelManager.checkBridgeAvailability()
        val result = localModelManager.isBridgeAvailableCached()
        return if (result == true) sharedLlamaEngine else StubLocalLlmEngine()
    }

    /**
     * Create an engine using a [LocalModelManager] synchronously.
     * Falls back to stub if bridge has not been checked yet.
     *
     * Only use when you are certain the bridge has already been initialized
     * (e.g., after LocalModelManager.initialize() completes).
     * For new call sites, prefer [ensureAndCreate].
     */
    fun create(config: ProviderConfig, localModelManager: LocalModelManager): LocalLlmEngine {
        if (config.kind != ProviderKind.localLlama) return StubLocalLlmEngine()
        val cached = localModelManager.isBridgeAvailableCached()
        if (cached == true) return sharedLlamaEngine
        if (cached == false) return StubLocalLlmEngine()
        // Cache is null — bridge not yet checked. Return stub with warning.
        Log.w(TAG, "Bridge availability not yet checked (cache=null). Returning StubLocalLlmEngine. " +
            "Call ensureAndCreate() instead to guarantee the bridge is checked.")
        return StubLocalLlmEngine()
    }

    /**
     * Create an engine without a [LocalModelManager].
     * Falls back to synchronous bridge check — do NOT call on main thread.
     */
    fun create(config: ProviderConfig): LocalLlmEngine {
        if (config.kind != ProviderKind.localLlama) return StubLocalLlmEngine()
        val available = try {
            LlamaCppBridge.isAvailable()
        } catch (_: Exception) { false }
        return if (available) sharedLlamaEngine else StubLocalLlmEngine()
    }
}
