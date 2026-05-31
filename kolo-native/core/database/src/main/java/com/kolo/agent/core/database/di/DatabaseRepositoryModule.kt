package com.kolo.agent.core.database.di

import com.kolo.agent.core.database.dao.MemoryDao
import com.kolo.agent.core.database.repository.RoomMemoryRepository
import com.kolo.agent.core.model.MemoryRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseRepositoryModule {

    @Provides
    @Singleton
    fun provideMemoryRepository(memoryDao: MemoryDao): MemoryRepository =
        RoomMemoryRepository(memoryDao)
}