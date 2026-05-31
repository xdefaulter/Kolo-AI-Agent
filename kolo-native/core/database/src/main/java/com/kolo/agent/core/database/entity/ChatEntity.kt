package com.kolo.agent.core.database.entity

import androidx.room.*
import com.kolo.agent.core.model.*

@Entity(
    tableName = "chats",
    foreignKeys = [
        ForeignKey(
            entity = FolderEntity::class,
            parentColumns = ["id"],
            childColumns = ["folder_id"],
            onDelete = ForeignKey.SET_NULL,
        )
    ],
    indices = [
        Index("updated_at"),
        Index("folder_id"),
    ]
)
data class ChatEntity(
    @PrimaryKey val id: String,
    val title: String,
    val provider_id: String? = null,
    val model_id: String? = null,
    val folder_id: String? = null,
    val created_at: Long,
    val updated_at: Long,
    val message_count: Int = 0,
    val is_pinned: Boolean = false,
    val unread_count: Int = 0,
)

fun ChatEntity.toDomain() = Chat(
    id = ChatId(id),
    title = title,
    providerId = provider_id?.let(::ProviderId),
    modelId = model_id,
    folderId = folder_id?.let(::FolderId),
    createdAt = created_at,
    updatedAt = updated_at,
    messageCount = message_count,
    isPinned = is_pinned,
    unreadCount = unread_count,
)

fun Chat.toEntity() = ChatEntity(
    id = id.value,
    title = title,
    provider_id = providerId?.value,
    model_id = modelId,
    folder_id = folderId?.value,
    created_at = createdAt,
    updated_at = updatedAt,
    message_count = messageCount,
    is_pinned = isPinned,
    unread_count = unreadCount,
)