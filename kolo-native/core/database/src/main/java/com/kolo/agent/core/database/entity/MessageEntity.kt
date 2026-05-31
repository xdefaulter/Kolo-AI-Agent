package com.kolo.agent.core.database.entity

import androidx.room.*
import com.kolo.agent.core.model.*

@Entity(
    tableName = "messages",
    foreignKeys = [
        ForeignKey(
            entity = ChatEntity::class,
            parentColumns = ["id"],
            childColumns = ["chat_id"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
    indices = [
        Index("chat_id", "created_at"),
    ]
)
data class MessageEntity(
    @PrimaryKey val id: String,
    val chat_id: String,
    val role: String,
    val content: String,
    val tool_call_id: String? = null,
    val tool_name: String? = null,
    val tool_success: Boolean? = null,
    val tool_calls_json: String? = null,
    val status: String? = null,
    val error: String? = null,
    val created_at: Long,
    val edited_at: Long? = null,
)

fun MessageEntity.toDomain(): Message {
    val toolCalls = tool_calls_json?.let {
        kotlinx.serialization.json.Json.decodeFromString<List<ToolCallInfo>>(it)
    }
    return Message(
        id = MessageId(id),
        chatId = ChatId(chat_id),
        role = MessageRole.fromWire(role),
        content = content,
        toolCallId = tool_call_id?.let(::ToolCallId),
        toolName = tool_name,
        toolSuccess = tool_success,
        toolCalls = toolCalls,
        status = status?.let { MessageStatus.valueOf(it) },
        error = error,
        createdAt = created_at,
        editedAt = edited_at,
    )
}

fun Message.toEntity() = MessageEntity(
    id = id.value,
    chat_id = chatId.value,
    role = role.wire,
    content = content,
    tool_call_id = toolCallId?.value,
    tool_name = toolName,
    tool_success = toolSuccess,
    tool_calls_json = toolCalls?.let {
        kotlinx.serialization.json.Json.encodeToString(
            kotlinx.serialization.builtins.ListSerializer(ToolCallInfo.serializer()),
            it
        )
    },
    status = status?.name,
    error = error,
    created_at = createdAt,
    edited_at = editedAt,
)