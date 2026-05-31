package com.kolo.agent.core.tools.registry

import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.model.ToolPermissionMode
import com.kolo.agent.core.model.api.ApiToolDefinition
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import com.kolo.agent.core.tools.ToolPlatform
import com.kolo.agent.core.tools.builtin.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Central registry for all built-in and custom tools.
 * Filters by platform, permissions, and provider disabled-tools config.
 */
class ToolRegistry {

    private val tools = mutableMapOf<String, KoloTool>()

    init {
        registerBuiltinTools()
    }

    private fun registerBuiltinTools() {
        register(CalculatorTool())
        register(DateTool())
        register(JsonParseTool())
        register(Base64Tool())
        register(HashTool())
        register(HttpGetTool())
        register(HttpPostTool())
        register(WebSearchTool())
        register(WebScrapeTool())
        register(RecallMemoriesTool())
        register(RememberThisTool())
        register(ForgetMemoryTool())
    }

    fun register(tool: KoloTool) {
        tools[tool.name] = tool
    }

    fun unregister(name: String) {
        tools.remove(name)
    }

    fun getTool(name: String): KoloTool? = tools[name]

    fun getAllTools(): List<KoloTool> = tools.values.toList()

    /** Get the default permission mode for a tool based on its permission level. */
    fun getDefaultPermissionMode(toolName: String): ToolPermissionMode {
        val tool = tools[toolName] ?: return ToolPermissionMode.askEveryTime
        return when (tool.permission) {
            ToolPermission.safe -> ToolPermissionMode.alwaysAllow
            ToolPermission.sensitive -> ToolPermissionMode.askEveryTime
            ToolPermission.dangerous -> ToolPermissionMode.askEveryTime
        }
    }

    fun getToolsForProvider(config: ProviderConfig): List<KoloTool> {
        return tools.values.filter { tool ->
            when (tool.platform) {
                ToolPlatform.ALL -> true
                ToolPlatform.ANDROID -> true
                ToolPlatform.IOS -> false
            }
            && tool.name !in config.disabledTools
            && (!config.smallModelMode || tool.permission != ToolPermission.dangerous)
        }
    }

    fun getToolDefinitionsForProvider(config: ProviderConfig): List<ApiToolDefinition> {
        return getToolsForProvider(config).map { it.toFunctionDefinition() }
    }

    suspend fun executeTool(
        name: String,
        arguments: String,
        chatId: String,
        providerConfig: ProviderConfig,
        context: android.content.Context? = null,
    ): ToolExecutionResult {
        val tool = tools[name]
            ?: return ToolExecutionResult.err("Unknown tool: $name")

        val params = try {
            val json = Json { ignoreUnknownKeys = true }
            val element = json.parseToJsonElement(arguments)
            if (element is JsonObject) {
                element.mapValues { (_, v) ->
                    when (v) {
                        is JsonPrimitive -> v.content
                        else -> v.toString()
                    }
                }
            } else emptyMap()
        } catch (_: Exception) {
            emptyMap()
        }

        val toolContext = ToolExecutionContext(
            chatId = chatId,
            androidContext = context,
        )

        return try {
            tool.execute(params, toolContext)
        } catch (e: Exception) {
            ToolExecutionResult.err("Tool '$name' execution failed: ${e.message}")
        }
    }
}

/**
 * Result of checking whether a tool can be auto-executed or needs user approval.
 */
sealed class ToolPermissionCheckResult {
    data object Allowed : ToolPermissionCheckResult()
    data class NeedsApproval(val permission: ToolPermission) : ToolPermissionCheckResult()
    data class Blocked(val reason: String) : ToolPermissionCheckResult()
}