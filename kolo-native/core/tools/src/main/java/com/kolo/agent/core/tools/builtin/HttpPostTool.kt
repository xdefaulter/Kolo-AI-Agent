package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI

class HttpPostTool : KoloTool() {
    override val name = "http_post"
    override val description = "Make an HTTP POST request with optional JSON body and return the response."
    override val parameterSchema = """{"type":"object","properties":{"url":{"type":"string","description":"URL to post to"},"body":{"type":"string","description":"Request body (JSON)"},"headers":{"type":"object","description":"Optional request headers"}},"required":["url"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val url = params["url"] ?: return ToolExecutionResult.err("Missing url parameter")
        val body = params["body"] ?: ""

        if (!validateUrlSafe(url)) {
            return ToolExecutionResult.err("URL validation failed: only external http/https URLs are allowed (internal/private/loopback hosts blocked)")
        }

        return try {
            val response = withContext(Dispatchers.IO) {
                val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "POST"
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15000
                connection.readTimeout = 30000
                connection.doOutput = true
                connection.setRequestProperty("User-Agent", "Kolo-Agent/1.0")
                connection.setRequestProperty("Content-Type", "application/json")

                params["headers"]?.let { headersJson ->
                    try {
                        val parsed = kotlinx.serialization.json.Json.parseToJsonElement(headersJson) as kotlinx.serialization.json.JsonObject
                        parsed.forEach { (k, v) ->
                            connection.setRequestProperty(k, v.jsonPrimitive.content)
                        }
                    } catch (_: Exception) { /* ignore bad headers JSON */ }
                }

                if (body.isNotEmpty()) {
                    connection.outputStream.bufferedWriter().use { it.write(body) }
                }

                val code = connection.responseCode
                val respBody = (if (code in 200..299) connection.inputStream else connection.errorStream)
                    ?.bufferedReader()?.use { it.readText() } ?: ""
                connection.disconnect()
                code to respBody
            }

            val (code, respBody) = response
            if (code in 200..299) {
                ToolExecutionResult.ok(respBody.take(50000))
            } else {
                ToolExecutionResult.err("HTTP $code: ${respBody.take(2000)}")
            }
        } catch (e: Exception) {
            ToolExecutionResult.err("HTTP POST error: ${e.message}")
        }
    }
}