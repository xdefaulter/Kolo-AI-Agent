package com.kolo.agent.core.database.entity

import androidx.room.*
import com.kolo.agent.core.model.*

@Entity(tableName = "folders")
data class FolderEntity(
    @PrimaryKey val id: String,
    val name: String,
    val color: Int? = null,
    val sort_index: Int = 0,
    val created_at: Long,
)

fun FolderEntity.toDomain() = Folder(
    id = FolderId(id),
    name = name,
    color = color,
    sortIndex = sort_index,
    createdAt = created_at,
)

fun Folder.toEntity() = FolderEntity(
    id = id.value,
    name = name,
    color = color,
    sort_index = sortIndex,
    created_at = createdAt,
)