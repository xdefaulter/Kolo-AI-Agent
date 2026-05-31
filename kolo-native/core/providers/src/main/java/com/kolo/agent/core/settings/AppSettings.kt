package com.kolo.agent.core.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * App-wide settings persisted via DataStore.
 */
class AppSettings(private val context: Context) {

    private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "kolo_settings")

    enum class ThemeMode { SYSTEM, LIGHT, DARK }

    private val KEY_THEME = stringPreferencesKey("theme_mode")
    private val KEY_DEFAULT_CHAT_FOLDER = stringPreferencesKey("default_chat_folder")

    val themeMode: Flow<ThemeMode> = context.dataStore.data.map { prefs ->
        prefs[KEY_THEME]?.let { ThemeMode.valueOf(it) } ?: ThemeMode.SYSTEM
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        context.dataStore.edit { it[KEY_THEME] = mode.name }
    }

    val defaultChatFolder: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[KEY_DEFAULT_CHAT_FOLDER]
    }

    suspend fun setDefaultChatFolder(folderId: String?) {
        context.dataStore.edit { prefs ->
            if (folderId != null) prefs[KEY_DEFAULT_CHAT_FOLDER] = folderId
            else prefs.remove(KEY_DEFAULT_CHAT_FOLDER)
        }
    }
}