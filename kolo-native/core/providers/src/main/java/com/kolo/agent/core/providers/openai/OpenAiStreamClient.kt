package com.kolo.agent.core.providers.openai

import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.api.ApiMessage
import com.kolo.agent.core.model.api.ApiToolDefinition
import com.kolo.agent.core.providers.ProviderConfigKeyStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import java.util.concurrent.TimeUnit

/**
 * OpenAI-compatible streaming chat client.
 *
 * Connects to any provider that implements the /v1/chat/completions endpoint
 * with SSE streaming support.
 */
class OpenAiStreamClient(
    private val client: OkHttpClient = defaultClient(),
) {
    companion object {
        private fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Stream a chat completion. Yields [StreamChunk]s as they arrive
     * from the SSE connection.
     */
    fun chatStream(
        config: ProviderConfig,
        messages: List<ApiMessage>,
        tools: List<ApiToolDefinition>? = null,
        model: String? = null,
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
    ): Flow<StreamChunk> = channelFlow {
        val activeModel = model
            ?: config.activeModel?.modelId
            ?: throw IllegalStateException("No model specified for provider ${config.name}")

        val requestJson = buildRequestBody(
            model = activeModel,
            messages = messages,
            tools = tools,
            maxTokens = maxTokens,
            temperature = temperature,
        )

        val url = config.baseUrl.trimEnd('/') + "/chat/completions"
        val requestBuilder = Request.Builder()
            .url(url)
            .post(requestJson.toRequestBody("application/json".toMediaType()))
            .header("Content-Type", "application/json")

        val apiKey = ProviderConfigKeyStore[config.id.value]
        if (apiKey.isNotBlank()) {
            requestBuilder.header("Authorization", "Bearer $apiKey")
        }
        config.customHeaders.forEach { (k, v) ->
            requestBuilder.header(k, v)
        }

        val eventSource = EventSources.createFactory(client)
            .newEventSource(requestBuilder.build(), object : EventSourceListener() {
                override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                    if (data == "[DONE]") {
                        channel.trySend(StreamChunk(finishReason = "stop"))
                        return
                    }
                    try {
                        val chunk = parseChunk(data)
                        channel.trySend(chunk)
                    } catch (_: Exception) {
                        // Skip malformed chunks
                    }
                }

                override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                    val errorMsg = t?.message ?: response?.body?.string()?.take(200) ?: "Unknown error"
                    channel.trySend(StreamChunk(error = errorMsg))
                    channel.close()
                }

                override fun onClosed(eventSource: EventSource) {
                    channel.close()
                }
            })

        awaitClose {
            eventSource.cancel()
        }
    }

    /**
     * Non-streaming chat completion. Returns the full response as JSON.
     */
    suspend fun chatComplete(
        config: ProviderConfig,
        messages: List<ApiMessage>,
        tools: List<ApiToolDefinition>? = null,
        model: String? = null,
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
    ): String {
        val activeModel = model
            ?: config.activeModel?.modelId
            ?: throw IllegalStateException("No model specified")

        val requestJson = buildRequestBody(
            model = activeModel,
            messages = messages,
            tools = tools,
            maxTokens = maxTokens,
            temperature = temperature,
            stream = false,
        )

        val url = config.baseUrl.trimEnd('/') + "/chat/completions"
        val requestBuilder = Request.Builder()
            .url(url)
            .post(requestJson.toRequestBody("application/json".toMediaType()))
            .header("Content-Type", "application/json")

        if (ProviderConfigKeyStore[config.id.value].isNotBlank()) {
            requestBuilder.header("Authorization", "Bearer ${ProviderConfigKeyStore[config.id.value]}")
        }
        config.customHeaders.forEach { (k, v) ->
            requestBuilder.header(k, v)
        }

        val response = client.newCall(requestBuilder.build()).execute()
        return response.body?.string() ?: throw IllegalStateException("Empty response")
    }

    /**
     * Fetch available models from the provider.
     */
    suspend fun fetchModels(config: ProviderConfig): List<Pair<String, String?>> = withContext(Dispatchers.IO) {
        val url = config.effectiveModelsUrl
        val requestBuilder = Request.Builder()
            .url(url)
            .get()
            .header("Content-Type", "application/json")

        if (ProviderConfigKeyStore[config.id.value].isNotBlank()) {
            requestBuilder.header("Authorization", "Bearer ${ProviderConfigKeyStore[config.id.value]}")
        }
        config.customHeaders.forEach { (k, v) ->
            requestBuilder.header(k, v)
        }

        val response = client.newCall(requestBuilder.build()).execute()
        val body = response.use { result ->
            if (!result.isSuccessful) return@withContext emptyList()
            result.body?.string() ?: return@withContext emptyList()
        }

        return@withContext try {
            val root = json.parseToJsonElement(body).jsonObject
            val modelsArray = root["data"]?.jsonArray
                ?: root["models"]?.jsonArray
                ?: return@withContext emptyList()
            modelsArray.mapNotNull { element ->
                val obj = element.jsonObject
                val name = obj["name"]?.jsonPrimitive?.contentOrNull
                val id = obj["id"]?.jsonPrimitive?.contentOrNull
                    ?: name
                    ?: return@mapNotNull null
                val displayName = obj["displayName"]?.jsonPrimitive?.contentOrNull
                    ?: obj["display_name"]?.jsonPrimitive?.contentOrNull
                val ownedBy = obj["owned_by"]?.jsonPrimitive?.contentOrNull
                id to (displayName ?: name?.takeIf { it != id } ?: ownedBy)
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun buildRequestBody(
        model: String,
        messages: List<ApiMessage>,
        tools: List<ApiToolDefinition>?,
        maxTokens: Int,
        temperature: Double,
        stream: Boolean = true,
    ): String {
        val request = buildJsonObject {
            put("model", model)
            put("messages", buildJsonArray {
                for (msg in messages) {
                    add(msg.toJson())
                }
            })
            put("max_tokens", maxTokens)
            put("temperature", temperature)
            put("stream", stream)
            tools?.let { defs ->
                if (defs.isNotEmpty()) {
                    put("tools", buildJsonArray {
                        for (def in defs) {
                            add(def.toJson())
                        }
                    })
                }
            }
        }
        return json.encodeToString(JsonObject.serializer(), request)
    }

    private fun parseChunk(data: String): StreamChunk {
        val root = json.parseToJsonElement(data).jsonObject
        val choices = root["choices"]?.jsonArray ?: return StreamChunk()

        if (choices.isEmpty()) return StreamChunk()

        val choice = choices[0].jsonObject
        val delta = choice["delta"]?.jsonObject ?: return StreamChunk()

        val content = delta["content"]?.jsonPrimitive?.contentOrNull ?: ""
        val finishReason = choice["finish_reason"]?.jsonPrimitive?.contentOrNull

        val reasoningContent = delta["reasoning_content"]?.jsonPrimitive?.contentOrNull

        val toolCallDeltas = delta["tool_calls"]?.jsonArray?.map { tc ->
            val tcObj = tc.jsonObject
            val index = tcObj["index"]?.jsonPrimitive?.intOrNull ?: 0
            val id = tcObj["id"]?.jsonPrimitive?.contentOrNull
            val name = tcObj["function"]?.jsonObject?.get("name")?.jsonPrimitive?.contentOrNull
            val argsFragment = tcObj["function"]?.jsonObject?.get("arguments")?.jsonPrimitive?.contentOrNull
            ToolCallDelta(index = index, id = id, name = name, argumentsFragment = argsFragment)
        }

        val usageObj = root["usage"]?.jsonObject
        val usage = usageObj?.let {
            UsageInfo(
                promptTokens = it["prompt_tokens"]?.jsonPrimitive?.intOrNull ?: 0,
                completionTokens = it["completion_tokens"]?.jsonPrimitive?.intOrNull ?: 0,
                totalTokens = it["total_tokens"]?.jsonPrimitive?.intOrNull ?: 0,
            )
        }

        return StreamChunk(
            content = content,
            toolCalls = toolCallDeltas,
            reasoningContent = reasoningContent,
            finishReason = finishReason,
            usage = usage,
        )
    }
}
