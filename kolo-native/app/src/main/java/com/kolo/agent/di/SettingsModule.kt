package com.kolo.agent.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
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

    // Single DataStore instance for the entire app — avoids the
    // "multiple DataStores active for the same file" crash.
    private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "kolo_settings")

    @Provides
    @Singleton
    fun provideDataStore(@ApplicationContext context: Context): DataStore<Preferences> =
        context.dataStore

    @Provides
    @Singleton
    fun provideAppSettings(dataStore: DataStore<Preferences>): AppSettings =
        AppSettings(dataStore)
}