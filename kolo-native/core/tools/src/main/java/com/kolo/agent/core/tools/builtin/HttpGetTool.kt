package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URI

class HttpGetTool : KoloTool() {
    override val name = "http_get"
    override val description = "Make an HTTP GET request and return the response body. Use for fetching web content or API data."
    override val parameterSchema = """{"type":"object","properties":{"url":{"type":"string","description":"URL to request"},"headers":{"type":"object","description":"Optional request headers"}},"required":["url"]}"""
    override val permission = ToolPermission.sensitive

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val url = params["url"] ?: return ToolExecutionResult.err("Missing url parameter")

        // Validate URL
        try {
            val uri = URI(url)
            if (uri.scheme !in listOf("http", "https")) {
                return ToolExecutionResult.err("Only http/https URLs are allowed")
            }
        } catch (e: Exception) {
            return ToolExecutionResult.err("Invalid URL: ${e.message}")
        }

        return try {
            val response = withContext(Dispatchers.IO) {
                val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 15000
                connection.readTimeout = 30000
                connection.setRequestProperty("User-Agent", "Kolo-Agent/1.0")

                val code = connection.responseCode
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                    .take(50000) // Truncate at 50KB

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