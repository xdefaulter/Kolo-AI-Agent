package com.kolo.agent.core.database.entity

import androidx.room.*
import com.kolo.agent.core.model.*

@Entity(
    tableName = "memories",
    indices = [Index("last_used_at")]
)
data class MemoryEntity(
    @PrimaryKey val id: String,
    val kind: String,
    val content: String,
    val source_chat_id: String? = null,
    val created_at: Long,
    val updated_at: Long,
    val last_used_at: Long,
    val use_count: Int = 0,
)

fun MemoryEntity.toDomain() = Memory(
    id = MemoryId(id),
    kind = kind,
    content = content,
    sourceChatId = source_chat_id?.let(::ChatId),
    createdAt = created_at,
    updatedAt = updated_at,
    lastUsedAt = last_used_at,
    useCount = use_count,
)

fun Memory.toEntity() = MemoryEntity(
    id = id.value,
    kind = kind,
    content = content,
    source_chat_id = sourceChatId?.value,
    created_at = createdAt,
    updated_at = updatedAt,
    last_used_at = lastUsedAt,
    use_count = useCount,
)