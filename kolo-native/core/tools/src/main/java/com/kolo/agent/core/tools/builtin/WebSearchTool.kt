package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URLEncoder

class WebSearchTool : KoloTool() {
    override val name = "web_search"
    override val description = "Search the web for information. Returns a list of results with titles, URLs, and snippets."
    override val parameterSchema = """{"type":"object","properties":{"query":{"type":"string","description":"Search query"},"max_results":{"type":"integer","description":"Maximum number of results (default: 5)"}},"required":["query"]}"""
    override val permission = ToolPermission.sensitive

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val query = params["query"] ?: return ToolExecutionResult.err("Missing query parameter")
        val maxResults = (params["max_results"]?.toIntOrNull() ?: 5).coerceIn(1, 10)

        return try {
            val results = withContext(Dispatchers.IO) {
                searchDuckDuckGo(query, maxResults)
            }
            if (results.isEmpty()) {
                ToolExecutionResult.ok("No results found for '$query'.")
            } else {
                ToolExecutionResult.ok(results)
            }
        } catch (e: Exception) {
            ToolExecutionResult.err("Web search error: ${e.message}")
        }
    }

    private fun searchDuckDuckGo(query: String, maxResults: Int): String {
        val encodedQuery = URLEncoder.encode(query, "UTF-8")
        val url = "https://html.duckduckgo.com/html/?q=$encodedQuery"

        val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 15000
        connection.readTimeout = 30000
        connection.setRequestProperty("User-Agent", "Kolo-Agent/1.0")

        val code = connection.responseCode
        if (code != 200) {
            return "Search request failed (HTTP $code)"
        }

        val html = connection.inputStream.bufferedReader().use { it.readText() }
        connection.disconnect()

        val results = mutableListOf<SearchResult>()
        // DuckDuckGo HTML results are in <div class="result results_links results_links_deep">
        // Each has <a class="result__a" href="...">Title</a> and <a class="result__snippet">Snippet</a>
        val resultRegex = Regex(
            """class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?class="result__snippet"[^>]*>(.*?)</a>""",
            RegexOption.DOT_MATCHES_ALL
        )
        val hrefRegex = Regex("""href="([^"]+)"""")
        val titleRegex = hrefRegex // reuse pattern
        val snippetRegex = Regex("""class="result__snippet"[^>]*>(.*?)</""", RegexOption.DOT_MATCHES_ALL)

        // Simpler parsing: find result blocks
        val resultBlocks = html.split("""class="result results_links"""".toRegex())
        for (block in resultBlocks.drop(1)) { // skip before first result
            if (results.size >= maxResults) break
            try {
                val titleMatch = Regex("""class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL).find(block)
                val snippetMatch = snippetRegex.find(block)

                if (titleMatch != null) {
                    val resultUrl = titleMatch.groupValues[1].let { ddgUrl ->
                        // DuckDuckGo wraps URLs; extract the actual URL
                        val uddgMatch = Regex("""uddg=([^&"]+)""").find(ddgUrl)
                        uddgMatch?.groupValues?.get(1)?.let { java.net.URLDecoder.decode(it, "UTF-8") } ?: ddgUrl
                    }
                    val title = titleMatch.groupValues[2].replace(Regex("<[^>]+>"), "").trim()
                    val snippet = snippetMatch?.groupValues?.get(1)?.replace(Regex("<[^>]+>"), "")?.trim() ?: ""

                    if (title.isNotBlank()) {
                        results.add(SearchResult(title, resultUrl, snippet))
                    }
                }
            } catch (_: Exception) { /* skip malformed blocks */ }
        }

        return buildString {
            appendLine("Web search results for '$query':")
            appendLine()
            results.forEachIndexed { i, r ->
                appendLine("${i + 1}. **${r.title}**")
                appendLine("   ${r.url}")
                if (r.snippet.isNotBlank()) appendLine("   ${r.snippet}")
                appendLine()
            }
        }
    }

    private data class SearchResult(val title: String, val url: String, val snippet: String)
}