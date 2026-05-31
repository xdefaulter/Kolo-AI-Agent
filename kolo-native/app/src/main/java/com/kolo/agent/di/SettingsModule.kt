package com.kolo.agent.di

import android.content.Context
import com.kolo.agent.core.settings.AppSettings
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object SettingsModule {

    @Provides
    @Singleton
    fun provideAppSettings(@ApplicationContext context: Context): AppSettings =
        AppSettings(context)
}