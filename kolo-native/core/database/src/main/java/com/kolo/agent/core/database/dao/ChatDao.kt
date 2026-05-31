package com.kolo.agent.core.database.dao

import androidx.room.*
import com.kolo.agent.core.database.entity.ChatEntity

@Dao
interface ChatDao {
    @Query("SELECT * FROM chats ORDER BY is_pinned DESC, updated_at DESC")
    suspend fun getAll(): List<ChatEntity>

    @Query("SELECT * FROM chats WHERE id = :id")
    suspend fun getById(id: String): ChatEntity?

    @Upsert
    suspend fun upsert(chat: ChatEntity)

    @Query("DELETE FROM chats WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM chats")
    suspend fun deleteAll()

    @Query("UPDATE chats SET folder_id = :folderId WHERE id = :chatId")
    suspend fun moveChatToFolder(chatId: String, folderId: String?)

    @Query("UPDATE chats SET is_pinned = :pinned WHERE id = :id")
    suspend fun setPinned(id: String, pinned: Boolean)

    @Query("UPDATE chats SET unread_count = :count WHERE id = :id")
    suspend fun setUnreadCount(id: String, count: Int)

    @Query("UPDATE chats SET title = :title, updated_at = :updatedAt WHERE id = :id")
    suspend fun updateTitle(id: String, title: String, updatedAt: Long = System.currentTimeMillis())

    @Query("UPDATE chats SET message_count = :count WHERE id = :id")
    suspend fun setMessageCount(id: String, count: Int)
}