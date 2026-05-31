package com.kolo.agent.core.providers.local

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
     * Check if a model file exists and is valid.
     */
    fun isValidModel(modelPath: String): Boolean = File(modelPath).exists()

    companion object {
        /** Known model search directories. */
        val MODEL_DIRS = listOf(
            "/sdcard/llm/models/",
            "/storage/emulated/0/llm/models/",
        )
    }
}

/**
 * Stub implementation of LocalLlmEngine.
 * Will be replaced with llama.cpp binding once integrated.
 */
class StubLocalLlmEngine : LocalLlmEngine {
    override val isModelLoaded: Boolean = false
    override val loadedModelPath: String? = null

    override suspend fun loadModel(modelPath: String, contextSize: Int, threads: Int) {
        throw UnsupportedOperationException("Local LLM not yet integrated. Install llama.cpp binding for local inference.")
    }

    override suspend fun unloadModel() {
        // No-op
    }

    override fun completeStream(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        repeatPenalty: Float,
    ): Flow<String> = flow {
        emit("[Local LLM not available — configure a cloud provider or integrate llama.cpp]")
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