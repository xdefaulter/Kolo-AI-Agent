package com.kolo.agent.core.database

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.kolo.agent.core.database.dao.*
import com.kolo.agent.core.database.entity.*

@Database(
    entities = [
        ChatEntity::class,
        MessageEntity::class,
        MemoryEntity::class,
        FolderEntity::class,
        PromptTemplateEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun chatDao(): ChatDao
    abstract fun messageDao(): MessageDao
    abstract fun memoryDao(): MemoryDao
    abstract fun folderDao(): FolderDao
    abstract fun promptTemplateDao(): PromptTemplateDao
}