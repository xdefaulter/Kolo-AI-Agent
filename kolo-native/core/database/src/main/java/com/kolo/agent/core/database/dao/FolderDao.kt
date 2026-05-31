package com.kolo.agent.core.database.dao

import androidx.room.*
import com.kolo.agent.core.database.entity.FolderEntity

@Dao
interface FolderDao {
    @Query("SELECT * FROM folders ORDER BY sort_index ASC, created_at ASC")
    suspend fun getAll(): List<FolderEntity>

    @Upsert
    suspend fun upsert(folder: FolderEntity)

    @Query("DELETE FROM folders WHERE id = :id")
    suspend fun deleteById(id: String)
}