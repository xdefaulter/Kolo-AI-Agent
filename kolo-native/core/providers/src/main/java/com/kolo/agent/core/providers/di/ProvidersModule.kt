package com.kolo.agent.core.providers.di

import android.content.Context
import com.kolo.agent.core.tools.permissions.ToolPermissionStore
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object ProvidersModule {

    @Provides
    @Singleton
    fun provideToolPermissionStore(@ApplicationContext context: Context): ToolPermissionStore =
        ToolPermissionStore(context)
}