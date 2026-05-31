package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.tools.ToolExecutionContext
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class WebSearchToolTest {

    private val tool = WebSearchTool()

    @Test
    fun toolMetadataIsCorrect() {
        assertEquals("web_search", tool.name)
        assertTrue(tool.description.isNotBlank())
        assertTrue(tool.description.contains("search", ignoreCase = true))
        assertEquals(com.kolo.agent.core.model.ToolPermission.sensitive, tool.permission)
    }

    @Test
    fun missingQueryReturnsError() = runTest {
        val result = tool.execute(emptyMap(), ToolExecutionContext(chatId = "test"))
        assertFalse(result.success)
        assertNotNull(result.error)
        assertTrue(result.error!!.contains("Missing query", ignoreCase = true))
    }

    @Test
    fun parameterSchemaIsValidJson() {
        val schema = tool.parameterSchema
        assertTrue(schema.contains("query"))
        assertTrue(schema.contains("max_results"))
        assertTrue("Schema must contain 'required' field", schema.contains("required"))
    }

    @Test
    fun executeDoesNotCrashWithEdgeCaseInput() = runTest {
        val result = tool.execute(
            mapOf("query" to "test", "max_results" to "1"),
            ToolExecutionContext(chatId = "test"),
        )
        assertNotNull(result)
    }

    @Test
    fun htmlParsingExtractsResultsFromValidHtml() {
        val html = """
            <html><body>
            <div class="result results_links results_links_deep">
                <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com&r=1">Example Title</a>
                <a class="result__snippet">This is the snippet text for example.</a>
            </div>
            <div class="result results_links results_links_deep">
                <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fanother.com&r=2">Another Result</a>
                <a class="result__snippet">Another snippet here.</a>
            </div>
            </body></html>
        """.trimIndent()

        val results = tool.parseDuckDuckGoHtml(html, 10)
        assertEquals("Should extract 2 results", 2, results.size)
        assertEquals("Example Title", results[0].title)
        assertTrue("URL should be decoded", results[0].url.contains("example.com"))
        assertTrue("Snippet should contain text", results[0].snippet.contains("snippet text"))
        assertEquals("Another Result", results[1].title)
    }

    @Test
    fun htmlParsingReturnsEmptyForNoResults() {
        val html = "<html><body><p>No results found.</p></body></html>"
        val results = tool.parseDuckDuckGoHtml(html, 10)
        assertTrue("Should have 0 results for empty HTML", results.isEmpty())
    }

    @Test
    fun urlExtractionDecodesUddgParameter() {
        assertEquals("https://www.example.com/path",
            tool.extractUrl("//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.example.com%2Fpath&r=1"))
    }

    @Test
    fun urlExtractionFallsBackToRawUrl() {
        assertEquals("https://raw-url.com/page",
            tool.extractUrl("https://raw-url.com/page"))
    }

    @Test
    fun formatResultsProducesStructuredOutput() {
        val results = listOf(
            WebSearchTool.SearchResult("Test Title", "https://example.com", "A snippet"),
        )
        val output = tool.formatResults("test query", results)
        assertTrue(output.contains("Test Title"))
        assertTrue(output.contains("https://example.com"))
        assertTrue(output.contains("A snippet"))
        assertTrue(output.contains("test query"))
    }

    @Test
    fun maxResultsLimitsParsing() {
        val html = buildString {
            append("<html><body>")
            for (i in 1..5) {
                append("""<div class="result results_links"><a class="result__a" href="//r">Result $i</a><a class="result__snippet">Snippet $i</a></div>""")
            }
            append("</body></html>")
        }
        val results = tool.parseDuckDuckGoHtml(html, 3)
        assertTrue("Should return at most 3 results, got ${results.size}", results.size <= 3)
    }

    @Test
    fun htmlParsingSkipsBlankTitles() {
        val html = """
            <div class="result results_links">
                <a class="result__a" href="//r"> </a>
                <a class="result__snippet">Snippet</a>
            </div>
        """.trimIndent()
        val results = tool.parseDuckDuckGoHtml(html, 10)
        assertEquals("Blank title results should be skipped", 0, results.size)
    }
}