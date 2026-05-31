package com.kolo.agent.core.providers.local

import android.content.Context
import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.ProviderKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
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
        // GGUF files start with the magic bytes "GGUF" (0x46475547 in little-endian)
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
 * Stub implementation of LocalLlmEngine.
 *
 * When llama.cpp Android binding (libllama.so) is available, replace this
 * with [LlamaCppEngine] which uses JNI to call llama.cpp for inference.
 *
 * To integrate llama.cpp:
 * 1. Add the llama.cpp Android AAR or build from source with CMake
 * 2. Create a C++ JNI bridge: llamodel-jni.cpp with functions:
 *    - Java_com_kolo_agent_core_providers_local_LlamaCppEngine_nativeLoadModel
 *    - Java_com_kolo_agent_core_providers_local_LlamaCppEngine_nativeComplete
 *    - Java_com_kolo_agent_core_providers_local_LlamaCppEngine_nativeFreeModel
 * 3. Replace [StubLocalLlmEngine] with [LlamaCppEngine] in [LlmEngineFactory]
 * 4. Add CMakeLists.txt pointing to llama.cpp sources
 * 5. Add NDK build config to core/providers/build.gradle.kts
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
        // Stub: would call nativeLoadModel(path, contextSize, threads) here
        isModelLoaded = true
        loadedModelPath = modelPath
    }

    override suspend fun unloadModel() {
        // Stub: would call nativeFreeModel() here
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
            emit("[Local LLM not available — configure a cloud provider or place a .gguf model in /sdcard/llm/models/]")
            return@flow
        }
        val modelFile = loadedModelPath?.let { File(it).name } ?: "unknown"
        emit("[Local LLM inference not yet integrated. Model '$modelFile' is loaded but llama.cpp binding is not available. " +
             "To enable local inference, integrate the llama.cpp Android NDK library.]")
    }.flowOn(Dispatchers.IO)
}

/**
 * Factory to create the appropriate engine based on provider config.
 */
object LlmEngineFactory {
    fun create(config: ProviderConfig): LocalLlmEngine {
        return when (config.kind) {
            ProviderKind.localLlama -> StubLocalLlmEngine()
            else -> StubLocalLlmEngine()
        }
    }
}