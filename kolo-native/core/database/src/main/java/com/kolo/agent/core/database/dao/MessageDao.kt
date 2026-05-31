package com.kolo.agent.core.database.dao

import androidx.room.*
import com.kolo.agent.core.database.entity.MessageEntity

@Dao
interface MessageDao {
    @Query("SELECT * FROM messages WHERE chat_id = :chatId ORDER BY created_at ASC, rowid ASC")
    suspend fun getForChat(chatId: String): List<MessageEntity>

    @Query("SELECT * FROM messages WHERE id = :id")
    suspend fun getById(id: String): MessageEntity?

    @Upsert
    suspend fun upsert(message: MessageEntity)

    @Query("DELETE FROM messages WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM messages WHERE chat_id = :chatId AND created_at > :cutoff")
    suspend fun deleteAfterTime(chatId: String, cutoff: Long)

    @Query("SELECT COUNT(*) FROM messages WHERE chat_id = :chatId")
    suspend fun countForChat(chatId: String): Int

    @Query("""
        SELECT m.* FROM messages m
        WHERE m.chat_id = :chatId AND LOWER(m.content) LIKE :query
        ORDER BY m.created_at DESC LIMIT :limit
    """)
    suspend fun searchInChat(chatId: String, query: String, limit: Int = 50): List<MessageEntity>

    @Query("""
        SELECT m.* FROM messages m
        JOIN chats c ON c.id = m.chat_id
        WHERE LOWER(m.content) LIKE :query
        ORDER BY m.created_at DESC LIMIT :limit
    """)
    suspend fun searchAll(query: String, limit: Int = 50): List<MessageEntity>
}