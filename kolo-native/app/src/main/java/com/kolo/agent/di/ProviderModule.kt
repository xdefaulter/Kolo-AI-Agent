package com.kolo.agent.di

import android.content.Context
import com.kolo.agent.core.database.dao.MemoryDao
import com.kolo.agent.core.database.repository.RoomMemoryRepository
import com.kolo.agent.core.model.MemoryRepository
import com.kolo.agent.core.providers.local.LocalModelManager
import com.kolo.agent.core.providers.ProviderRepository
import com.kolo.agent.core.providers.openai.OpenAiStreamClient
import com.kolo.agent.core.providers.secure.SecureKeyStore
import com.kolo.agent.core.settings.AppSettings
import com.kolo.agent.core.tools.permissions.ToolPermissionStore
import com.kolo.agent.core.tools.registry.ToolRegistry
import com.kolo.agent.feature.phonecontrol.*
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object ProviderModule {

    @Provides
    @Singleton
    fun provideSecureKeyStore(@ApplicationContext context: Context): SecureKeyStore =
        SecureKeyStore(context)

    @Provides
    @Singleton
    fun provideProviderRepository(
        @ApplicationContext context: Context,
        secureKeyStore: SecureKeyStore,
    ): ProviderRepository = ProviderRepository(context, secureKeyStore)

    @Provides
    @Singleton
    fun provideOpenAiStreamClient(): OpenAiStreamClient = OpenAiStreamClient()

    @Provides
    @Singleton
    fun provideLocalModelManager(
        @ApplicationContext context: Context,
        appSettings: AppSettings,
    ): LocalModelManager = LocalModelManager(context, appSettings)
}