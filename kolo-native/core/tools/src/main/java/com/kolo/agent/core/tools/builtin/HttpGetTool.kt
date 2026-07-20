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

class HttpGetTool : KoloTool() {
    override val name = "http_get"
    override val description = "Make an HTTP GET request and return the response body. Use for fetching web content or API data."
    override val parameterSchema = """{"type":"object","properties":{"url":{"type":"string","description":"URL to request"},"headers":{"type":"object","description":"Optional request headers"}},"required":["url"]}"""
    override val permission = ToolPermission.sensitive

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val url = params["url"] ?: return ToolExecutionResult.err("Missing url parameter")

        if (!validateUrlSafe(url)) {
            return ToolExecutionResult.err("URL validation failed: only external http/https URLs are allowed (internal/private/loopback hosts blocked)")
        }

        return try {
            val response = withContext(Dispatchers.IO) {
                val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "GET"
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15000
                connection.readTimeout = 30000
                connection.setRequestProperty("User-Agent", "Kolo-Agent/1.0")

                params["headers"]?.let { headersJson ->
                    try {
                        val parsed = kotlinx.serialization.json.Json.parseToJsonElement(headersJson) as kotlinx.serialization.json.JsonObject
                        parsed.forEach { (k, v) ->
                            connection.setRequestProperty(k, v.jsonPrimitive.content)
                        }
                    } catch (_: Exception) { /* ignore bad headers JSON */ }
                }

                val code = connection.responseCode
                val body = (if (code in 200..299) connection.inputStream else connection.errorStream)
                    ?.bufferedReader()?.use { it.readText() }
                    ?.take(50000) ?: ""
                connection.disconnect()
                code to body
            }

            val (code, body) = response
            if (code in 200..299) {
                ToolExecutionResult.ok(body.take(50000))
            } else {
                ToolExecutionResult.err("HTTP $code: ${body.take(2000)}")
            }
        } catch (e: Exception) {
            ToolExecutionResult.err("HTTP GET error: ${e.message}")
        }
    }
}