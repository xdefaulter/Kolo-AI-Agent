package com.kolo.agent.core.tools.builtin

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext

class JsonParseTool : KoloTool() {
    override val name = "json_parse"
    override val description = "Parse and extract values from a JSON string. Returns formatted, human-readable output."
    override val parameterSchema = """{"type":"object","properties":{"json":{"type":"string","description":"JSON string to parse"},"path":{"type":"string","description":"Dot-separated path to extract (e.g. 'data.items.0.name')"}},"required":["json"]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val jsonStr = params["json"] ?: return ToolExecutionResult.err("Missing json parameter")
        val path = params["path"]

        return try {
            val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true; prettyPrint = true }
            val element = json.parseToJsonElement(jsonStr)

            val result = if (path != null) {
                extractPath(element, path)
            } else {
                json.encodeToString(kotlinx.serialization.json.JsonElement.serializer(), element)
            }

            ToolExecutionResult.ok(result.toString())
        } catch (e: Exception) {
            ToolExecutionResult.err("JSON parse error: ${e.message}")
        }
    }

    private fun extractPath(element: kotlinx.serialization.json.JsonElement, path: String): Any {
        var current = element
        for (key in path.split(".")) {
            when (current) {
                is kotlinx.serialization.json.JsonObject -> {
                    current = current[key]
                        ?: return "Path not found: $key"
                }
                is kotlinx.serialization.json.JsonArray -> {
                    val index = key.toIntOrNull()
                        ?: return "Invalid array index: $key"
                    if (index < 0 || index >= current.size) return "Index out of bounds: $index"
                    current = current[index]
                }
                else -> return "Cannot traverse into primitive at $key"
            }
        }
        return current
    }
}