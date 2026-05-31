package com.kolo.agent.core.model

import kotlinx.serialization.Serializable

/**
 * A chat conversation / thread.
 */
@Serializable
data class Chat(
    val id: ChatId = ChatId(java.util.UUID.randomUUID().toString()),
    val title: String = "New Chat",
    val providerId: ProviderId? = null,
    val modelId: String? = null,
    val folderId: FolderId? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val messageCount: Int = 0,
    val isPinned: Boolean = false,
    val unreadCount: Int = 0,
)

/**
 * A single message within a chat.
 */
@Serializable
data class Message(
    val id: MessageId = MessageId(java.util.UUID.randomUUID().toString()),
    val chatId: ChatId,
    val role: MessageRole,
    val content: String,
    val toolCallId: ToolCallId? = null,
    val toolName: String? = null,
    val toolSuccess: Boolean? = null,
    val toolCalls: List<ToolCallInfo>? = null,
    val status: MessageStatus? = null,
    val error: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val editedAt: Long? = null,
)

@Serializable
enum class MessageRole {
    system, user, assistant, tool;

    val wire: String get() = name

    companion object {
        fun fromWire(s: String): MessageRole =
            entries.firstOrNull { it.wire == s } ?: user
    }
}

@Serializable
enum class MessageStatus {
    sending, delivered, error, cancelled
}

/**
 * A parsed tool call from the model's response.
 */
@Serializable
data class ToolCallInfo(
    val id: String,
    val name: String,
    val arguments: String, // JSON string
)

/**
 * A memory entry persisted for agent recall.
 */
@Serializable
data class Memory(
    val id: MemoryId = MemoryId(java.util.UUID.randomUUID().toString()),
    val kind: String,
    val content: String,
    val sourceChatId: ChatId? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val lastUsedAt: Long = System.currentTimeMillis(),
    val useCount: Int = 0,
)

/**
 * A folder for organizing chats.
 */
@Serializable
data class Folder(
    val id: FolderId = FolderId(java.util.UUID.randomUUID().toString()),
    val name: String,
    val color: Int? = null,
    val sortIndex: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
)

/**
 * A prompt template.
 */
@Serializable
data class PromptTemplate(
    val id: TemplateId = TemplateId(java.util.UUID.randomUUID().toString()),
    val name: String,
    val body: String,
    val tags: List<String> = emptyList(),
    val useCount: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)

/**
 * A single search hit from message search.
 */
data class MessageSearchHit(
    val messageId: MessageId,
    val chatId: ChatId,
    val chatTitle: String,
    val role: MessageRole,
    val snippet: String,
    val createdAt: Long,
)