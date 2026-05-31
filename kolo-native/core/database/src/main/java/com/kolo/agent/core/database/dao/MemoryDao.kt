package com.kolo.agent.core.database.dao

import androidx.room.*
import com.kolo.agent.core.database.entity.MemoryEntity

@Dao
interface MemoryDao {
    @Query("SELECT * FROM memories ORDER BY last_used_at DESC")
    suspend fun getAll(): List<MemoryEntity>

    @Query("SELECT * FROM memories ORDER BY last_used_at DESC LIMIT :limit")
    suspend fun getAll(limit: Int): List<MemoryEntity>

    @Query("SELECT * FROM memories WHERE id = :id")
    suspend fun getById(id: String): MemoryEntity?

    @Upsert
    suspend fun upsert(memory: MemoryEntity)

    @Query("DELETE FROM memories WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM memories")
    suspend fun deleteAll()

    @Query("UPDATE memories SET last_used_at = :timestamp, use_count = use_count + 1 WHERE id = :id")
    suspend fun touch(id: String, timestamp: Long = System.currentTimeMillis())

    @Query("UPDATE memories SET last_used_at = :timestamp, use_count = use_count + 1 WHERE id IN (:ids)")
    suspend fun touchBatch(ids: List<String>, timestamp: Long = System.currentTimeMillis())

    @Query("""
        SELECT * FROM memories
        WHERE LOWER(content) LIKE :query
        ORDER BY last_used_at DESC LIMIT :limit
    """)
    suspend fun search(query: String, limit: Int = 6): List<MemoryEntity>
}