package com.kolo.agent.core.providers.local

import android.util.Log

/**
 * JNI bridge to llama.cpp for local LLM inference.
 *
 * This class provides a diagnostic path to check whether the native
 * llama.cpp library is available on the device. When the library is
 * not packaged (as is the current state), all native methods return
 * safe defaults indicating the library is unavailable.
 *
 * To enable local inference:
 * 1. Package the official llama.cpp .so files for arm64-v8a and x86_64
 * 2. Place GGUF models in /sdcard/llm/models/
 * 3. The native methods will then function for real inference
 *
 * Until then, [isAvailable] always returns false and [loadModel] returns 0.
 */
object LlamaCppBridge {
    private const val TAG = "LlamaCppBridge"

    /**
     * Check if the llama.cpp native library is available.
     * Returns true only if libllama.so (or equivalent) is packaged
     * and can be loaded successfully.
     */
    fun isAvailable(): Boolean {
        return try {
            System.loadLibrary("llama")
            Log.i(TAG, "llama.cpp native library loaded successfully")
            nativeRuntimeAvailable()
        } catch (e: UnsatisfiedLinkError) {
            Log.i(TAG, "llama.cpp native library not available: ${e.message}")
            false
        } catch (e: Exception) {
            Log.w(TAG, "Error checking llama.cpp availability: ${e.message}")
            false
        }
    }

    /**
     * Load a GGUF model file.
     * Returns a native handle (long) or 0 on failure.
     * Only works if [isAvailable] returns true.
     */
    fun loadModel(modelPath: String, contextSize: Int = 4096, threads: Int = 4): Long {
        if (!isAvailable()) return 0L
        return try {
            nativeLoadModel(modelPath, contextSize, threads)
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Native loadModel failed: ${e.message}")
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
            "[Local LLM error: ${e.message}]"
        }
    }

    // ──── Native methods (implemented in llama_bridge.cpp) ────
    // These will throw UnsatisfiedLinkError until libllama.so is packaged.

    @Suppress("FunctionName")
    private external fun nativeRuntimeAvailable(): Boolean

    @Suppress("FunctionName")
    private external fun nativeLoadModel(modelPath: String, contextSize: Int, threads: Int): Long

    @Suppress("FunctionName")
    private external fun nativeUnloadModel(handle: Long)

    @Suppress("FunctionName")
    private external fun nativeComplete(
        handle: Long, prompt: String, maxTokens: Int,
        temperature: Float, topP: Float, repeatPenalty: Float,
    ): String
}