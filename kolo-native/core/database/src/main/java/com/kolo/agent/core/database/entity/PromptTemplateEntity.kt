package com.kolo.agent.core.database.entity

import androidx.room.*
import com.kolo.agent.core.model.*

@Entity(tableName = "prompt_templates")
data class PromptTemplateEntity(
    @PrimaryKey val id: String,
    val name: String,
    val body: String,
    val tags: String? = null,
    val use_count: Int = 0,
    val created_at: Long,
    val updated_at: Long,
)

fun PromptTemplateEntity.toDomain() = PromptTemplate(
    id = TemplateId(id),
    name = name,
    body = body,
    tags = tags?.split(",")?.filter { it.isNotEmpty() } ?: emptyList(),
    useCount = use_count,
    createdAt = created_at,
    updatedAt = updated_at,
)

fun PromptTemplate.toEntity() = PromptTemplateEntity(
    id = id.value,
    name = name,
    body = body,
    tags = tags.takeIf { it.isNotEmpty() }?.joinToString(","),
    use_count = useCount,
    created_at = createdAt,
    updated_at = updatedAt,
)