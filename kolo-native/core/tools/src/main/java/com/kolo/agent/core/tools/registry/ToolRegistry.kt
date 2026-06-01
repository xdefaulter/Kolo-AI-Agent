package com.kolo.agent.core.tools.registry

import com.kolo.agent.core.model.CustomToolDef
import com.kolo.agent.core.model.CustomToolKind
import com.kolo.agent.core.model.ProviderConfig
import com.kolo.agent.core.model.Skill
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
    private val builtinNames = mutableSetOf<String>()
    private var customTools: List<CustomToolDef> = emptyList()
    private var skills: List<Skill> = emptyList()

    init {
        registerBuiltinTools()
        builtinNames.addAll(tools.keys)
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
        register(ClipboardReadTool())
        register(ClipboardWriteTool())
        register(DeviceInfoTool())
        register(ConnectivityTool())
        register(BatteryInfoTool())
        register(VibrateTool())
        register(ListInstalledAppsTool())
        register(LaunchAppTool())
        register(TimerTool())
        register(ContactsSearchTool())
        register(LocationTool())
        register(ListSkillsTool { skills })
        register(ReadSkillTool { skills })
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

    fun setCustomTools(definitions: List<CustomToolDef>) {
        customTools.forEach { tools.remove(it.name) }
        customTools = definitions
        definitions
            .filter { it.name.isNotBlank() && it.name !in builtinNames }
            .forEach { register(CustomToolAdapter(it)) }
    }

    fun setSkills(definitions: List<Skill>) {
        skills = definitions.sortedBy { it.name.lowercase() }
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
        subLlmCall: (suspend (String, String) -> String)? = null,
    ): ToolExecutionResult {
        val params = parseArguments(arguments)
        return executeParsedTool(name, params, chatId, providerConfig, context, subLlmCall, depth = 0)
    }

    private suspend fun executeParsedTool(
        name: String,
        params: Map<String, String>,
        chatId: String,
        providerConfig: ProviderConfig,
        context: android.content.Context?,
        subLlmCall: (suspend (String, String) -> String)?,
        depth: Int,
    ): ToolExecutionResult {
        if (depth > 6) return ToolExecutionResult.err("Composed tool depth limit reached.")
        val tool = tools[name]
            ?: return ToolExecutionResult.err("Unknown tool: $name")

        val toolContext = ToolExecutionContext(
            chatId = chatId,
            androidContext = context,
            subLlmCall = subLlmCall,
            runToolByName = { toolName, toolParams ->
                executeParsedTool(toolName, toolParams, chatId, providerConfig, context, subLlmCall, depth + 1)
            },
            getToolByName = { toolName -> tools[toolName] },
        )

        return try {
            tool.execute(params, toolContext)
        } catch (e: Exception) {
            ToolExecutionResult.err("Tool '$name' execution failed: ${e.message}")
        }
    }

    private fun parseArguments(arguments: String): Map<String, String> {
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
        return params
    }
}

private class CustomToolAdapter(private val def: CustomToolDef) : KoloTool() {
    override val name: String = def.name
    override val description: String = def.description
    override val parameterSchema: String = def.parameterSchema.ifBlank {
        """{"type":"object","properties":{},"required":[]}"""
    }
    override val permission: ToolPermission = def.permission

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        return when (def.kind) {
            CustomToolKind.prompt -> executePrompt(params, context)
            CustomToolKind.composed -> executeComposed(params, context)
        }
    }

    private suspend fun executePrompt(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val systemPrompt = def.systemPrompt.ifBlank { def.description }
        val userMessage = renderTemplate(def.userMessage.ifBlank { "{{input}}" }, params)
        val call = context.subLlmCall
            ?: return ToolExecutionResult.err("Prompt custom tool needs a remote active provider.")
        val output = call(systemPrompt, userMessage)
        return ToolExecutionResult.ok(output, mapOf("custom_tool_id" to def.id.value, "kind" to "prompt"))
    }

    private suspend fun executeComposed(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val runTool = context.runToolByName
            ?: return ToolExecutionResult.err("Composed custom tool cannot call sub-tools in this context.")
        if (def.steps.isEmpty()) return ToolExecutionResult.err("Custom tool has no composed steps.")
        val values = params.toMutableMap()
        val outputs = mutableListOf<String>()
        def.steps.forEachIndexed { index, step ->
            val subTool = context.getToolByName?.invoke(step.toolName)
            if (subTool?.permission == ToolPermission.dangerous) {
                return ToolExecutionResult.err("Step ${index + 1} (${step.toolName}) is dangerous and cannot run inside a composed custom tool.")
            }
            if (subTool?.permission == ToolPermission.sensitive && permission == ToolPermission.safe) {
                return ToolExecutionResult.err("Step ${index + 1} (${step.toolName}) is sensitive; mark this custom tool as sensitive or dangerous.")
            }
            val rendered = step.params.mapValues { (_, value) -> renderTemplate(value, values) }
            val result = runTool(step.toolName, rendered)
            if (!result.success) {
                return ToolExecutionResult.err("Step ${index + 1} (${step.toolName}) failed: ${result.error}")
            }
            outputs.add("[${index + 1}] ${step.toolName}\n${result.output}")
            values["_previous"] = result.output
        }
        return ToolExecutionResult.ok(outputs.joinToString("\n\n"), mapOf("custom_tool_id" to def.id.value, "kind" to "composed"))
    }
}

private class ListSkillsTool(private val skillsProvider: () -> List<Skill>) : KoloTool() {
    override val name = "list_skills"
    override val description = "List saved Kolo skills with their names and descriptions."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val enabled = skillsProvider().filter { it.isEnabled }
        if (enabled.isEmpty()) return ToolExecutionResult.ok("(no enabled skills)")
        return ToolExecutionResult.ok(enabled.joinToString("\n") { "- ${it.name}: ${it.description}" })
    }
}

private class ReadSkillTool(private val skillsProvider: () -> List<Skill>) : KoloTool() {
    override val name = "read_skill"
    override val description = "Read the full instructions for one saved Kolo skill by name."
    override val parameterSchema = """{"type":"object","properties":{"name":{"type":"string","description":"Skill name"}},"required":["name"]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val name = params["name"]?.trim().orEmpty()
        val skill = skillsProvider().firstOrNull { it.isEnabled && it.name.equals(name, ignoreCase = true) }
            ?: return ToolExecutionResult.err("Skill '$name' was not found or is disabled.")
        return ToolExecutionResult.ok(skill.content, mapOf("skill_id" to skill.id.value))
    }
}

private fun renderTemplate(template: String, values: Map<String, String>): String {
    return Regex("""\{\{\s*([a-zA-Z0-9_]+)\s*}}""").replace(template) { match ->
        values[match.groupValues[1]].orEmpty()
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
