package com.kolo.agent.core.providers.local

import android.util.Log
import androidx.annotation.Keep

@Keep
fun interface LlamaTokenCallback {
    fun onToken(token: String): Boolean
}

/**
 * JNI bridge to llama.cpp for local LLM inference.
 *
 * The official llama.cpp sources are compiled into libkolo_llama_bridge.so.
 * GGUF model files are supplied by path at runtime.
 *
 * IMPORTANT: [isAvailable] calls [System.loadLibrary] on first invocation.
 * It must NEVER be called from the main thread. The [libraryLoaded] cache
 * ensures subsequent calls are fast and safe from any thread.
 */
object LlamaCppBridge {
    private const val TAG = "LlamaCppBridge"
    private const val DEFAULT_GPU_LAYERS = 0
    @Volatile private var libraryLoaded: Boolean? = null

    /**
     * Check if the llama.cpp native library is available.
     *
     * First call loads the native library (System.loadLibrary) — must be off main thread.
     * Subsequent calls return the cached result instantly.
     */
    fun isAvailable(): Boolean {
        libraryLoaded?.let { return it }
        return try {
            System.loadLibrary("kolo_llama_bridge")
            val available = nativeRuntimeAvailable()
            libraryLoaded = available
            Log.i(TAG, "llama.cpp bridge loaded: available=$available")
            available
        } catch (e: UnsatisfiedLinkError) {
            libraryLoaded = false
            Log.w(TAG, "llama.cpp bridge not available: ${e.message}")
            false
        } catch (e: Exception) {
            libraryLoaded = false
            Log.w(TAG, "Error checking llama.cpp availability: ${e.message}")
            false
        }
    }

    /** Returns true if [isAvailable] has been called at least once and cached the result. */
    fun isCached(): Boolean = libraryLoaded != null

    /** Returns the cached result, or null if never checked. */
    fun cachedAvailability(): Boolean? = libraryLoaded

    /**
     * Load a GGUF model file.
     * Returns a native handle (long) or 0 on failure.
     * Only works if [isAvailable] returns true.
     */
    fun loadModel(
        modelPath: String,
        contextSize: Int = 4096,
        threads: Int = 4,
        gpuLayers: Int = DEFAULT_GPU_LAYERS,
    ): Long {
        if (!isAvailable()) {
            Log.e(TAG, "loadModel called but bridge unavailable")
            return 0L
        }
        return try {
            var handle = nativeLoadModel(modelPath, contextSize, threads, gpuLayers.coerceAtLeast(0))
            if (handle == 0L && gpuLayers > 0) {
                Log.w(TAG, "GPU offload load failed; retrying CPU-only model load")
                handle = nativeLoadModel(modelPath, contextSize, threads, 0)
            }
            if (handle == 0L) {
                Log.e(TAG, "nativeLoadModel returned 0 for: $modelPath")
            } else {
                Log.i(TAG, "Model loaded: $modelPath (handle=$handle)")
            }
            handle
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Native loadModel failed: ${e.message}")
            0L
        } catch (e: Exception) {
            Log.e(TAG, "loadModel exception: ${e.message}")
            0L
        }
    }

    /**
     * Unload a previously loaded model.
     */
    fun unloadModel(handle: Long) {
        if (handle == 0L) return
        try {
            nativeUnloadModel(handle)
            Log.i(TAG, "Model unloaded (handle=$handle)")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Native unloadModel failed: ${e.message}")
        }
    }

    /**
     * Generate text completion using a loaded model.
     * Returns the generated text, or an error message on failure.
     */
    fun complete(handle: Long, prompt: String, maxTokens: Int = 4096,
                 temperature: Float = 0.7f, topP: Float = 0.95f,
                 repeatPenalty: Float = 1.1f): String {
        if (handle == 0L) return "[Local LLM not available]"
        return try {
            nativeComplete(handle, prompt, maxTokens, temperature, topP, repeatPenalty)
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Native complete failed: ${e.message}")
            "[Local LLM error: ${e.message}]"
        }
    }

    fun completeStream(
        handle: Long,
        prompt: String,
        maxTokens: Int = 4096,
        temperature: Float = 0.7f,
        topP: Float = 0.95f,
        repeatPenalty: Float = 1.1f,
        onToken: (String) -> Boolean,
    ): String {
        if (handle == 0L) return "Local LLM not available"
        return try {
            nativeCompleteStream(
                handle = handle,
                prompt = prompt,
                maxTokens = maxTokens,
                temperature = temperature,
                topP = topP,
                repeatPenalty = repeatPenalty,
                callback = LlamaTokenCallback(onToken),
            )
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Native completeStream failed: ${e.message}")
            "Local LLM error: ${e.message}"
        } catch (e: Exception) {
            Log.e(TAG, "completeStream exception: ${e.message}")
            "Local LLM error: ${e.message}"
        }
    }

    // ──── Native methods (implemented in llama_bridge.cpp) ────

    @Suppress("FunctionName")
    private external fun nativeRuntimeAvailable(): Boolean

    @Suppress("FunctionName")
    private external fun nativeLoadModel(
        modelPath: String,
        contextSize: Int,
        threads: Int,
        gpuLayers: Int,
    ): Long

    @Suppress("FunctionName")
    private external fun nativeUnloadModel(handle: Long)

    @Suppress("FunctionName")
    private external fun nativeComplete(
        handle: Long, prompt: String, maxTokens: Int,
        temperature: Float, topP: Float, repeatPenalty: Float,
    ): String

    @Suppress("FunctionName")
    private external fun nativeCompleteStream(
        handle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        repeatPenalty: Float,
        callback: LlamaTokenCallback,
    ): String
}
