package com.kolo.agent.core.tools

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.model.api.ApiFunctionDef
import com.kolo.agent.core.model.api.ApiToolDefinition
import com.kolo.agent.core.model.api.parseParameterSchema

/**
 * Base class for all Kolo tools.
 */
abstract class KoloTool {
    abstract val name: String
    abstract val description: String
    abstract val parameterSchema: String // JSON schema string
    abstract val permission: ToolPermission

    open val platform: ToolPlatform = ToolPlatform.ALL

    abstract suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult

    /**
     * Convert this tool's definition to the OpenAI function-calling format.
     * The [parameterSchema] string is parsed into a [JsonObject] — never sent raw.
     */
    fun toFunctionDefinition(): ApiToolDefinition = ApiToolDefinition(
        type = "function",
        function = ApiFunctionDef(
            name = name,
            description = description,
            parameters = parseParameterSchema(parameterSchema),
        )
    )
}

enum class ToolPlatform {
    ALL, ANDROID, IOS
}

data class ToolExecutionContext(
    val chatId: String,
    val androidContext: android.content.Context? = null,
    val permissionChecker: suspend (ToolPermission) -> Boolean = { true },
    val subLlmCall: (suspend (String, String) -> String)? = null,
    val runToolByName: (suspend (String, Map<String, String>) -> ToolExecutionResult)? = null,
    val getToolByName: ((String) -> KoloTool?)? = null,
)
