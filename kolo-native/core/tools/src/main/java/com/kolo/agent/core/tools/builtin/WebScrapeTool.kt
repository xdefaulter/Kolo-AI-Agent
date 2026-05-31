package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext

class WebScrapeTool : KoloTool() {
    override val name = "web_scrape"
    override val description = "Scrape and extract text content from a web page URL."
    override val parameterSchema = """{"type":"object","properties":{"url":{"type":"string","description":"URL to scrape"},"selector":{"type":"string","description":"Optional CSS selector to target specific content"}},"required":["url"]}"""
    override val permission = ToolPermission.sensitive

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val url = params["url"] ?: return ToolExecutionResult.err("Missing url parameter")
        // Reuse HttpGetTool logic for basic scraping
        val httpGet = HttpGetTool()
        return httpGet.execute(params, context)
    }
}