package com.kolo.agent.core.database.dao

import androidx.room.*
import com.kolo.agent.core.database.entity.PromptTemplateEntity

@Dao
interface PromptTemplateDao {
    @Query("SELECT * FROM prompt_templates ORDER BY use_count DESC, updated_at DESC")
    suspend fun getAll(): List<PromptTemplateEntity>

    @Upsert
    suspend fun upsert(template: PromptTemplateEntity)

    @Query("DELETE FROM prompt_templates WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE prompt_templates SET use_count = use_count + 1, updated_at = :updatedAt WHERE id = :id")
    suspend fun touch(id: String, updatedAt: Long = System.currentTimeMillis())
}