package com.kolo.agent.core.model.api

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

/**
 * Typed API message models for the OpenAI chat completions endpoint.
 * Replaces the previous Map<String, String> approach with proper serializable types.
 */

@Serializable
data class ApiMessage(
    val role: String,
    val content: String? = null,
    val contentParts: List<ApiContentPart>? = null,
    val name: String? = null,
    val toolCalls: List<ApiToolCall>? = null,
    val toolCallId: String? = null,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("role", role)
        if (!contentParts.isNullOrEmpty()) {
            put("content", buildJsonArray {
                contentParts.forEach { add(it.toJson()) }
            })
        } else if (content != null) {
            put("content", content)
        } else {
            put("content", JsonNull)
        }
        name?.let { put("name", it) }
        toolCalls?.let { calls ->
            put("tool_calls", buildJsonArray {
                for (call in calls) {
                    add(call.toJson())
                }
            })
        }
        toolCallId?.let { put("tool_call_id", it) }
    }
}

@Serializable
data class ApiContentPart(
    val type: String,
    val text: String? = null,
    val imageUrl: String? = null,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("type", type)
        when (type) {
            "text" -> put("text", text.orEmpty())
            "image_url" -> put("image_url", buildJsonObject {
                put("url", imageUrl.orEmpty())
            })
        }
    }
}

@Serializable
data class ApiToolCall(
    val id: String,
    val type: String = "function",
    val function: ApiFunctionCall,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("id", id)
        put("type", type)
        put("function", function.toJson())
    }
}

@Serializable
data class ApiFunctionCall(
    val name: String,
    val arguments: String,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("name", name)
        put("arguments", arguments)
    }
}

/**
 * A tool/function definition in the OpenAI API format.
 */
@Serializable
data class ApiToolDefinition(
    val type: String = "function",
    val function: ApiFunctionDef,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("type", type)
        put("function", function.toJson())
    }
}

@Serializable
data class ApiFunctionDef(
    val name: String,
    val description: String,
    val parameters: JsonObject,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("name", name)
        put("description", description)
        put("parameters", parameters)
    }
}

/**
 * Helper: parse a parameterSchema JSON string into a JsonObject.
 * If the string is not valid JSON, wraps it as a default object schema.
 */
fun parseParameterSchema(schema: String): JsonObject {
    return try {
        Json.parseToJsonElement(schema).jsonObject
    } catch (_: Exception) {
        buildJsonObject {
            put("type", "object")
            put("properties", buildJsonObject {})
        }
    }
}
