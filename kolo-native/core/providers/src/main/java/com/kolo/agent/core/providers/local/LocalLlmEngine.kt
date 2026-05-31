package com.kolo.agent.core.providers.local

import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.ProviderKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Interface for local LLM inference via llama.cpp.
 *
 * This provides a unified API for running models locally on device.
 * The actual implementation will use the llama.cpp Android binding
 * once integrated.
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
        val file = File(modelPath)
        if (!file.exists() || file.length() < 64) return false
        return try {
            file.inputStream().use { stream ->
                val magic = ByteArray(4)
                stream.read(magic)
                magic[0] == 'G'.code.toByte() &&
                magic[1] == 'G'.code.toByte() &&
                magic[2] == 'U'.code.toByte() &&
                magic[3] == 'F'.code.toByte()
            }
        } catch (_: Exception) { false }
    }

    /**
     * List available GGUF models in known directories.
     */
    fun listAvailableModels(): List<ModelInfo> {
        return MODEL_DIRS.flatMap { dir ->
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

    companion object {
        /** Known model search directories. */
        val MODEL_DIRS = listOf(
            "/sdcard/llm/models/",
            "/storage/emulated/0/llm/models/",
        )
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
        get() = when {
            sizeBytes >= 1_000_000_000 -> "%.1f GB".format(sizeBytes / 1_000_000_000.0)
            sizeBytes >= 1_000_000 -> "%.1f MB".format(sizeBytes / 1_000_000.0)
            else -> "%.1f KB".format(sizeBytes / 1_000.0)
        }
}

/**
 * JNI-backed llama.cpp engine.
 *
 * This class is intentionally strict: it validates GGUF files and then asks
 * the native bridge whether an official llama.cpp runtime is present. If the
 * bridge is compiled but `libllama.so` is not packaged, the user gets a clear
 * runtime error instead of a fake local answer.
 *
 * **LOCAL INFERENCE IS NOT FUNCTIONAL YET.** The C++ bridge and CMake config
 * exist but no `.so` is packaged. [LlamaCppBridge.isAvailable()] returns false.
 */
class LlamaCppEngine : LocalLlmEngine {
    override var isModelLoaded: Boolean = false
        private set
    override var loadedModelPath: String? = null
        private set
    private var nativeHandle: Long = 0L

    override suspend fun loadModel(modelPath: String, contextSize: Int, threads: Int) {
        if (!isValidModel(modelPath)) {
            throw IllegalArgumentException("Model file not found or not a valid GGUF file: $modelPath")
        }
        if (!LlamaCppBridge.isAvailable()) {
            throw IllegalStateException(
                "llama.cpp is not available in this build. " +
                "Package the official libllama.so and set a model path to enable inference."
            )
        }
        nativeHandle = withContext(Dispatchers.IO) {
            LlamaCppBridge.loadModel(modelPath, contextSize, threads)
        }
        if (nativeHandle == 0L) {
            throw IllegalStateException("llama.cpp failed to load model: $modelPath")
        }
        isModelLoaded = true
        loadedModelPath = modelPath
    }

    override suspend fun unloadModel() {
        if (nativeHandle != 0L && LlamaCppBridge.isAvailable()) {
            withContext(Dispatchers.IO) { LlamaCppBridge.unloadModel(nativeHandle) }
        }
        nativeHandle = 0L
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
        if (!isModelLoaded) {
            emit("[Local LLM not loaded — configure a provider or place a .gguf model in /sdcard/llm/models/]")
            return@flow
        }
        if (!LlamaCppBridge.isAvailable()) {
            emit("[Local LLM bridge unavailable — llama.cpp runtime is not packaged in this build.]")
            return@flow
        }
        val response = withContext(Dispatchers.IO) {
            LlamaCppBridge.complete(nativeHandle, prompt, maxTokens, temperature, topP, repeatPenalty)
        }
        emit(response)
    }.flowOn(Dispatchers.IO)
}

/**
 * Fallback used only when the native bridge is unavailable.
 * **Local inference is not functional.** This stub exists so the app
 * doesn't crash when a provider config references localLlama.
 */
class StubLocalLlmEngine : LocalLlmEngine {
    override var isModelLoaded: Boolean = false
        private set
    override var loadedModelPath: String? = null
        private set

    override suspend fun loadModel(modelPath: String, contextSize: Int, threads: Int) {
        if (!isValidModel(modelPath)) {
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
        emit("[Local LLM inference is not available in this build. The model at ${loadedModelPath ?: "unknown"} is loaded in stub mode. To enable local inference, integrate the llama.cpp Android NDK library.]")
    }.flowOn(Dispatchers.IO)
}

/**
 * Factory to create the appropriate engine based on provider config.
 */
object LlmEngineFactory {
    fun create(config: ProviderConfig): LocalLlmEngine {
        return when (config.kind) {
            ProviderKind.localLlama -> if (LlamaCppBridge.isAvailable()) LlamaCppEngine() else StubLocalLlmEngine()
            else -> StubLocalLlmEngine()
        }
    }
}