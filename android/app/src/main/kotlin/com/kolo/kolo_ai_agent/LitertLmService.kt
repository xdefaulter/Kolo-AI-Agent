package com.kolo.kolo_ai_agent

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.*
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Manages the LiteRT-LM engine lifecycle and provides inference calls
 * to the Flutter side via MethodChannel and EventChannel.
 *
 * Architecture:
 *   Flutter (Dart) ──MethodChannel──▸ LitertLmService ──▸ LiteRT-LM Engine (native)
 *   Flutter (Dart) ◂──EventChannel── LitertLmService ◂── streaming tokens
 *
 * The engine is loaded on a background thread (Dispatchers.IO) since
 * initialize() can take seconds. Streaming tokens are pushed through the
 * EventChannel sink so the Flutter UI updates in real-time.
 *
 * Backend strategy: NPU only. These models are Tensor G5 AOT packages, so
 * silently falling back to GPU/CPU hides the failure mode we need to fix.
 */
class LitertLmService(private val context: Context) {
    companion object {
        private const val TAG = "LitertLmService"
        const val METHOD_CHANNEL = "com.kolo.ai/litert_lm"
        const val EVENT_CHANNEL = "com.kolo.ai/litert_lm_stream"
    }

    private var engine: Engine? = null
    private val isInitialized = AtomicBoolean(false)
    private val isInferenceRunning = AtomicBoolean(false)
    private var activeBackend: String = "unknown"

    // EventChannel sink for streaming tokens to Flutter
    private var eventSink: EventChannel.EventSink? = null

    // Coroutine scope for background work
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Inference job so we can cancel it
    private var inferenceJob: Job? = null

    var state: String = "notLoaded" // notLoaded, loading, running, error, stopped
        private set

    /**
     * Set up MethodChannel and EventChannel handlers on the Flutter
     * engine. Call once from MainActivity.configureFlutterEngine().
     */
    fun setupMethodChannel(
        methodChannel: MethodChannel,
        eventChannel: EventChannel
    ) {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> handleInitialize(call, result)
                "startChat" -> handleStartChat(call, result)
                "chatSync" -> handleChatSync(call, result)
                "cancelInference" -> handleCancelInference(result)
                "close" -> handleClose(result)
                "getState" -> result.success(state)
                "getActiveBackend" -> result.success(activeBackend)
                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun handleInitialize(call: MethodCall, result: MethodChannel.Result) {
        val modelPath = call.argument<String>("modelPath") ?: run {
            result.error("INVALID", "modelPath is required", null)
            return
        }
        val requestedBackend = call.argument<String>("backend") ?: "NPU"
        if (!requestedBackend.equals("NPU", ignoreCase = true)) {
            result.error(
                "NPU_REQUIRED",
                "LiteRT-LM Tensor G5 packages must run with backend=NPU; got $requestedBackend",
                null
            )
            return
        }

        if (isInitialized.get()) {
            closeEngine()
        }

        state = "loading"
        serviceScope.launch {
            try {
                val nativeLibDir = context.applicationInfo.nativeLibraryDir
                val modelFile = File(modelPath)
                if (!modelFile.isFile) {
                    throw IllegalArgumentException("Model file does not exist: $modelPath")
                }
                val dispatchLib = File(nativeLibDir, "libLiteRtDispatch_GoogleTensor.so")
                if (!dispatchLib.isFile) {
                    throw IllegalStateException(
                        "Missing Google Tensor dispatch library at ${dispatchLib.absolutePath}"
                    )
                }

                Log.i(TAG, "Initializing LiteRT-LM with backend=NPU, model=$modelPath")
                Log.i(TAG, "Native library dir: $nativeLibDir")
                val engineConfig = EngineConfig(
                    modelPath = modelPath,
                    backend = Backend.NPU(nativeLibDir),
                    cacheDir = context.cacheDir.absolutePath,
                )
                val candidateEngine = Engine(engineConfig)
                candidateEngine.initialize()

                engine = candidateEngine
                activeBackend = "NPU"
                isInitialized.set(true)
                state = "running"
                Log.i(TAG, "LiteRT-LM engine initialized successfully with backend=NPU")
                withContext(Dispatchers.Main) {
                    result.success(true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize LiteRT-LM engine", e)
                state = "error"
                activeBackend = "unknown"
                engine = null
                isInitialized.set(false)
                val message = formatInitError(e)
                withContext(Dispatchers.Main) {
                    result.error("INIT_FAILED", message, null)
                }
            }
        }
    }

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

    private fun handleStartChat(call: MethodCall, result: MethodChannel.Result) {
        if (!isInitialized.get() || engine == null) {
            result.error("NOT_INITIALIZED", "Engine not initialized", null)
            return
        }
        if (!isInferenceRunning.compareAndSet(false, true)) {
            result.error("BUSY", "LiteRT-LM inference is already running", null)
            return
        }

        val text = call.argument<String>("text") ?: ""
        val systemInstruction = call.argument<String>("systemInstruction") ?: ""

        inferenceJob = serviceScope.launch {
            try {
                val conversationConfig = if (systemInstruction.isNotEmpty()) {
                    ConversationConfig(Contents.of(systemInstruction))
                } else {
                    ConversationConfig()
                }
                val conv = engine!!.createConversation(conversationConfig)
                try {
                    // sendMessageAsync(String, Map?) returns Flow<Message>
                    val flow = conv.sendMessageAsync(text, emptyMap<String, Any>())
                    flow.collect { message ->
                        // Extract text from Contents → List<Content> → Content.Text
                        val sb = StringBuilder()
                        for (content in message.contents.contents) {
                            if (content is Content.Text) {
                                sb.append(content.text)
                            }
                        }
                        val textChunk = sb.toString()
                        if (textChunk.isNotEmpty()) {
                            eventSink?.success(textChunk)
                        }
                    }
                    eventSink?.success("__DONE__")
                } finally {
                    conv.close()
                }
            } catch (e: CancellationException) {
                eventSink?.success("__DONE__")
            } catch (e: Exception) {
                Log.e(TAG, "Inference error", e)
                eventSink?.success("__ERROR__:${e.message}")
            } finally {
                isInferenceRunning.set(false)
                inferenceJob = null
            }
        }
        result.success(null) // Acknowledge — tokens will stream via EventChannel
    }

    private fun handleChatSync(call: MethodCall, result: MethodChannel.Result) {
        if (!isInitialized.get() || engine == null) {
            result.error("NOT_INITIALIZED", "Engine not initialized", null)
            return
        }
        if (!isInferenceRunning.compareAndSet(false, true)) {
            result.error("BUSY", "LiteRT-LM inference is already running", null)
            return
        }

        val text = call.argument<String>("text") ?: ""
        val systemInstruction = call.argument<String>("systemInstruction") ?: ""

        inferenceJob = serviceScope.launch {
            try {
                val conversationConfig = if (systemInstruction.isNotEmpty()) {
                    ConversationConfig(Contents.of(systemInstruction))
                } else {
                    ConversationConfig()
                }
                val conv = engine!!.createConversation(conversationConfig)
                try {
                    val response = conv.sendMessage(text)
                    // Extract text from Contents → List<Content> → Content.Text
                    val sb = StringBuilder()
                    for (content in response.contents.contents) {
                        if (content is Content.Text) {
                            sb.append(content.text)
                        }
                    }
                    withContext(Dispatchers.Main) {
                        result.success(sb.toString())
                    }
                } finally {
                    conv.close()
                }
            } catch (e: CancellationException) {
                Log.i(TAG, "Sync inference cancelled")
                withContext(Dispatchers.Main) {
                    result.error("CANCELLED", "LiteRT-LM inference cancelled", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Sync inference error", e)
                withContext(Dispatchers.Main) {
                    result.error("INFERENCE_FAILED", e.message, null)
                }
            } finally {
                isInferenceRunning.set(false)
                inferenceJob = null
            }
        }
    }

    private fun handleCancelInference(result: MethodChannel.Result) {
        inferenceJob?.cancel()
        result.success(true)
    }

    private fun handleClose(result: MethodChannel.Result) {
        closeEngine()
        result.success(true)
    }

    private fun closeEngine() {
        inferenceJob?.cancel()
        inferenceJob = null
        isInferenceRunning.set(false)
        try {
            engine?.close()
        } catch (_: Exception) {}
        engine = null
        isInitialized.set(false)
        activeBackend = "unknown"
        state = "stopped"
    }

    fun destroy() {
        closeEngine()
        serviceScope.cancel()
    }
}
