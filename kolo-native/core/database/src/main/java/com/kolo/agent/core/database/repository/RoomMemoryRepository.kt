package com.kolo.agent.core.database.repository

import com.kolo.agent.core.database.dao.MemoryDao
import com.kolo.agent.core.database.entity.toDomain
import com.kolo.agent.core.database.entity.toEntity
import com.kolo.agent.core.model.ChatId
import com.kolo.agent.core.model.Memory
import com.kolo.agent.core.model.MemoryRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Room-backed implementation of [MemoryRepository].
 * Injected via Hilt into memory tools.
 */
@Singleton
class RoomMemoryRepository @Inject constructor(
    private val memoryDao: MemoryDao,
) : MemoryRepository {

    override suspend fun search(query: String, limit: Int): List<Memory> {
        return memoryDao.search("%${query.lowercase()}%", limit).map { it.toDomain() }
    }

    override suspend fun touchBatch(ids: List<String>) {
        memoryDao.touchBatch(ids)
    }

    override suspend fun save(memory: Memory): Memory {
        val entity = memory.toEntity()
        memoryDao.upsert(entity)
        return memory.copy(
            createdAt = entity.created_at,
            updatedAt = entity.updated_at,
            lastUsedAt = entity.last_used_at,
        )
    }

    override suspend fun deleteById(id: String) {
        memoryDao.deleteById(id)
    }

    suspend fun getAll(): List<Memory> =
        memoryDao.getAll().map { it.toDomain() }

    suspend fun getById(id: String): Memory? =
        memoryDao.getById(id)?.toDomain()
}