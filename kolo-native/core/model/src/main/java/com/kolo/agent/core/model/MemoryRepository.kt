package com.kolo.agent.core.model

/**
 * Shared memory repository interface for tool injection.
 * Implemented by Room-backed repository in core:database.
 */
interface MemoryRepository {
    suspend fun search(query: String, limit: Int = 6): List<Memory>
    suspend fun touchBatch(ids: List<String>)
    suspend fun save(memory: Memory): Memory
    suspend fun deleteById(id: String)
}