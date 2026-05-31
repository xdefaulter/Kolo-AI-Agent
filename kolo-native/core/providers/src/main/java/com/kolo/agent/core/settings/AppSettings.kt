package com.kolo.agent.core.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * App-wide settings persisted via DataStore.
 *
 * IMPORTANT: This class must be provided as a singleton via Hilt
 * (see [SettingsModule]). Do NOT instantiate directly — the DataStore
 * delegate requires single ownership or it crashes with
 * "There are multiple DataStores active for the same file".
 */
class AppSettings(private val dataStore: DataStore<Preferences>) {

    enum class ThemeMode { SYSTEM, LIGHT, DARK }

    private val KEY_THEME = stringPreferencesKey("theme_mode")
    private val KEY_DEFAULT_CHAT_FOLDER = stringPreferencesKey("default_chat_folder")

    val themeMode: Flow<ThemeMode> = dataStore.data.map { prefs ->
        prefs[KEY_THEME]?.let { ThemeMode.valueOf(it) } ?: ThemeMode.SYSTEM
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        dataStore.edit { it[KEY_THEME] = mode.name }
    }

    val defaultChatFolder: Flow<String?> = dataStore.data.map { prefs ->
        prefs[KEY_DEFAULT_CHAT_FOLDER]
    }

    suspend fun setDefaultChatFolder(folderId: String?) {
        dataStore.edit { prefs ->
            if (folderId != null) prefs[KEY_DEFAULT_CHAT_FOLDER] = folderId
            else prefs.remove(KEY_DEFAULT_CHAT_FOLDER)
        }
    }
}