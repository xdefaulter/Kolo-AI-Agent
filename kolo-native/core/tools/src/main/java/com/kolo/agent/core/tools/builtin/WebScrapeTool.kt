package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext

class WebScrapeTool : KoloTool() {
    override val name = "web_scrape"
    override val description = "Scrape and extract text content from a web page URL."
    override val parameterSchema = """{"type":"object","properties":{"url":{"type":"string","description":"URL to scrape"},"selector":{"type":"string","description":"Optional HTML tag name (e.g. 'div', 'span', 'p') to target specific content"}},"required":["url"]}"""
    override val permission = ToolPermission.sensitive

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val url = params["url"] ?: return ToolExecutionResult.err("Missing url parameter")
        val selector = params["selector"]
        val httpGet = HttpGetTool()
        val result = httpGet.execute(params + ("url" to url), context)
        if (!result.success) return result

        var html = result.output
        if (!selector.isNullOrBlank()) {
            // Only allow simple HTML tag names (letters/digits, must start with a letter)
            // to prevent regex injection via the selector value.
            if (!Regex("^[a-zA-Z][a-zA-Z0-9]*$").matches(selector)) {
                return ToolExecutionResult.err("Invalid HTML tag name: '$selector'. Only simple tag names (letters/digits) are supported.")
            }
            // Simple tag-based extraction: find content between tags matching the selector
            // This is a simplified approach — not a full CSS selector engine
            val tagMatch = Regex("<($selector)[^>]*>(.*?)</$selector>", RegexOption.DOT_MATCHES_ALL)
            val matches = tagMatch.findAll(html).map { it.groupValues[2] }.toList()
            if (matches.isNotEmpty()) {
                html = matches.joinToString("\n\n")
            }
        }

        // Strip HTML tags to get plain text
        val text = html
            .replace(Regex("<script[^>]*>.*?</script>", RegexOption.DOT_MATCHES_ALL), "")
            .replace(Regex("<style[^>]*>.*?</style>", RegexOption.DOT_MATCHES_ALL), "")
            .replace(Regex("<[^>]+>"), "")
            .replace(Regex("&nbsp;"), " ")
            .replace(Regex("&amp;"), "&")
            .replace(Regex("&lt;"), "<")
            .replace(Regex("&gt;"), ">")
            .replace(Regex("&quot;"), "\"")
            .replace(Regex("\n{3,}"), "\n\n")
            .trim()

        return if (text.isBlank()) {
            ToolExecutionResult.ok("[No text content extracted from $url]")
        } else {
            ToolExecutionResult.ok(text.take(50000))
        }
    }
}