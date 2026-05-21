package com.kolo.kolo_ai_agent

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class LitertLmSmokeTestActivity : Activity() {
    private val scope = CoroutineScope(Dispatchers.IO)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val modelPath = intent.getStringExtra("modelPath")
        val prompt = intent.getStringExtra("prompt") ?: "Say OK."
        val systemInstruction = intent.getStringExtra("systemInstruction") ?: ""

        scope.launch {
            var engine: Engine? = null
            try {
                require(!modelPath.isNullOrBlank()) { "modelPath extra is required" }

                val modelFile = File(modelPath)
                require(modelFile.isFile) { "Model file does not exist: $modelPath" }

                val nativeLibDir = applicationInfo.nativeLibraryDir
                val dispatchLib = File(nativeLibDir, "libLiteRtDispatch_GoogleTensor.so")
                require(dispatchLib.isFile) {
                    "Missing Google Tensor dispatch library: ${dispatchLib.absolutePath}"
                }

                Log.i(TAG, "SMOKE_START backend=NPU model=$modelPath")
                Log.i(TAG, "SMOKE_NATIVE_LIB_DIR $nativeLibDir")

                engine = Engine(
                    EngineConfig(
                        modelPath = modelPath,
                        backend = Backend.NPU(nativeLibDir),
                        cacheDir = cacheDir.absolutePath,
                    )
                )
                engine.initialize()
                Log.i(TAG, "SMOKE_INITIALIZED backend=NPU")

                val conversationConfig = if (systemInstruction.isNotBlank()) {
                    ConversationConfig(Contents.of(systemInstruction))
                } else {
                    ConversationConfig()
                }
                val conversation = engine.createConversation(conversationConfig)
                try {
                    val response = conversation.sendMessage(prompt)
                    val text = buildString {
                        for (content in response.contents.contents) {
                            if (content is Content.Text) append(content.text)
                        }
                    }
                    Log.i(TAG, "SMOKE_RESPONSE ${text.take(500)}")
                    Log.i(TAG, "SMOKE_SUCCESS backend=NPU")
                } finally {
                    conversation.close()
                }
            } catch (t: Throwable) {
                Log.e(TAG, "SMOKE_FAILED ${formatInitError(t)}", t)
            } finally {
                try {
                    engine?.close()
                } catch (_: Throwable) {
                }
                withContext(Dispatchers.Main) {
                    finish()
                }
            }
        }
    }

    companion object {
        private const val TAG = "LitertLmSmokeTest"

        private fun formatInitError(t: Throwable): String {
            val detail = t.message ?: t.toString()
            val looksLikeNpuDispatchFailure =
                detail.contains("Failed to create engine", ignoreCase = true) ||
                    detail.contains("DISPATCH_OP", ignoreCase = true) ||
                    detail.contains("litert_compiled_model", ignoreCase = true)

            if (!looksLikeNpuDispatchFailure) return detail

            return "Tensor G5 NPU access was denied by Android's EdgeTPU service. " +
                "The app must be EdgeTPU-allowlisted and signature-matched, usually through " +
                "Google Play On-device AI / Play AI Pack delivery. Original error: $detail"
        }
    }
}
