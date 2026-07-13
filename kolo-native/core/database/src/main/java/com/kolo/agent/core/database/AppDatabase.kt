package com.kolo.agent.core.database

import androidx.room.AutoMigration
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
    version = 2,
    exportSchema = true,
    autoMigrations = [
        AutoMigration(from = 1, to = 2),
    ],
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun chatDao(): ChatDao
    abstract fun messageDao(): MessageDao
    abstract fun memoryDao(): MemoryDao
    abstract fun folderDao(): FolderDao
    abstract fun promptTemplateDao(): PromptTemplateDao

    companion object {
        fun builder(context: android.content.Context): RoomDatabase.Builder<AppDatabase> {
            return androidx.room.Room.databaseBuilder(
                context,
                AppDatabase::class.java,
                "kolo.db"
            ).fallbackToDestructiveMigrationOnDowngrade()
        }
    }
}
