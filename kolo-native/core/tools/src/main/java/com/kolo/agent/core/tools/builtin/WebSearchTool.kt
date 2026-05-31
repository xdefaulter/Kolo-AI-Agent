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
    override val parameterSchema = """{"type":"object","properties":{"query":{"type":"string","description":"Search query"},"max_results":{"type":"integer","description":"Maximum number of results (default: 5, max: 10)"}},"required":["query"]}"""
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
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) Kolo-Agent/1.0")
        connection.setRequestProperty("Accept", "text/html")
        connection.instanceFollowRedirects = true

        val code = connection.responseCode
        if (code != 200) {
            connection.disconnect()
            // Fallback: try the lite version
            return searchDuckDuckGoLite(query, maxResults)
        }

        val html = connection.inputStream.bufferedReader().use { it.readText() }
        connection.disconnect()

        val results = parseDuckDuckGoHtml(html, maxResults)
        if (results.isEmpty()) {
            // Fallback to lite version
            return searchDuckDuckGoLite(query, maxResults)
        }

        return formatResults(query, results)
    }

    private fun searchDuckDuckGoLite(query: String, maxResults: Int): String {
        val encodedQuery = URLEncoder.encode(query, "UTF-8")
        val url = "https://lite.duckduckgo.com/lite/?q=$encodedQuery"

        return try {
            val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) Kolo-Agent/1.0")

            if (connection.responseCode != 200) {
                connection.disconnect()
                return "Web search failed (HTTP ${connection.responseCode}). Please try again later."
            }

            val html = connection.inputStream.bufferedReader().use { it.readText() }
            connection.disconnect()

            val results = parseDuckDuckGoLiteHtml(html, maxResults)
            if (results.isEmpty()) {
                return "No results found for '$query'."
            }
            formatResults(query, results)
        } catch (e: Exception) {
            "Web search error: ${e.message}"
        }
    }

    private data class SearchResult(val title: String, val url: String, val snippet: String)

    private fun parseDuckDuckGoHtml(html: String, maxResults: Int): List<SearchResult> {
        val results = mutableListOf<SearchResult>()

        // Primary parser: find result blocks with class="result"
        val resultBlocks = html.split("""class="result"""".toRegex())
        for (block in resultBlocks.drop(1)) {
            if (results.size >= maxResults) break
            try {
                val titleMatch = Regex("""class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL).find(block)
                val snippetMatch = Regex("""class="result__snippet"[^>]*>(.*?)</""", RegexOption.DOT_MATCHES_ALL).find(block)

                if (titleMatch != null) {
                    val rawUrl = titleMatch.groupValues[1]
                    val resultUrl = extractUrl(rawUrl)
                    val title = titleMatch.groupValues[2].replace(Regex("<[^>]+>"), "").trim()
                    val snippet = snippetMatch?.groupValues?.get(1)?.replace(Regex("<[^>]+>"), "")?.trim() ?: ""

                    if (title.isNotBlank()) {
                        results.add(SearchResult(title, resultUrl, snippet))
                    }
                }
            } catch (_: Exception) { /* skip malformed blocks */ }
        }

        // Fallback parser: find all <a> tags with href containing "uddg="
        if (results.isEmpty()) {
            val linkPattern = Regex("""<a[^>]*href="([^"]+uddg=[^"]+)"[^>]*>([^<]+)</a>""")
            for (match in linkPattern.findAll(html)) {
                if (results.size >= maxResults) break
                val url = extractUrl(match.groupValues[1])
                val title = match.groupValues[2].trim()
                if (title.isNotBlank() && !title.startsWith("http") && url.startsWith("http")) {
                    results.add(SearchResult(title, url, ""))
                }
            }
        }

        return results
    }

    private fun parseDuckDuckGoLiteHtml(html: String, maxResults: Int): List<SearchResult> {
        val results = mutableListOf<SearchResult>()
        // Lite version uses table rows; try to extract links and snippets
        val linkPattern = Regex("""<a[^>]*class="result-link"[^>]*href="([^"]+)"[^>]*>(.*?)</a>""", RegexOption.DOT_MATCHES_ALL)
        val snippetPattern = Regex("""<td[^>]*class="result-snippet"[^>]*>(.*?)</td>""", RegexOption.DOT_MATCHES_ALL)

        val links = linkPattern.findAll(html).toList()
        val snippets = snippetPattern.findAll(html).toList()

        for (i in links.indices) {
            if (i >= maxResults) break
            val link = links[i]
            val url = extractUrl(link.groupValues[1])
            val title = link.groupValues[2].replace(Regex("<[^>]+>"), "").trim()
            val snippet = if (i < snippets.size) snippets[i].groupValues[1].replace(Regex("<[^>]+>"), "").trim() else ""
            if (title.isNotBlank()) {
                results.add(SearchResult(title, url, snippet))
            }
        }

        // Fallback: any <a> with uddg=
        if (results.isEmpty()) {
            val uddgPattern = Regex("""href="(https?://[^"]+)"[^>]*>([^<]{3,})</a>""")
            for (match in uddgPattern.findAll(html)) {
                if (results.size >= maxResults) break
                val url = match.groupValues[1]
                val title = match.groupValues[2].trim()
                if (title.isNotBlank() && url.startsWith("http")) {
                    results.add(SearchResult(title, url, ""))
                }
            }
        }

        return results
    }

    private fun extractUrl(rawUrl: String): String {
        // DuckDuckGo wraps URLs via /uddg= parameter
        val uddgMatch = Regex("""uddg=([^&"]+)""").find(rawUrl)
        return uddgMatch?.groupValues?.get(1)?.let { java.net.URLDecoder.decode(it, "UTF-8") } ?: rawUrl
    }

    private fun formatResults(query: String, results: List<SearchResult>): String = buildString {
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