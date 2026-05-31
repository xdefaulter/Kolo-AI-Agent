package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

class DateTool : KoloTool() {
    override val name = "date"
    override val description = "Get the current date, time, and timezone. Useful for time-sensitive queries."
    override val parameterSchema = """{"type":"object","properties":{"format":{"type":"string","description":"DateTime format pattern (default: ISO local datetime)"}},"required":[]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val now = ZonedDateTime.now()
        val format = params["format"] ?: "yyyy-MM-dd HH:mm:ss z"
        val formatted = try {
            now.format(DateTimeFormatter.ofPattern(format))
        } catch (_: Exception) {
            now.format(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
        }
        return ToolExecutionResult.ok(buildString {
            appendLine("Current date and time: $formatted")
            appendLine("Timezone: ${now.zone}")
            appendLine("Unix timestamp: ${now.toEpochSecond()}")
            appendLine("Day of week: ${now.dayOfWeek}")
        })
    }
}