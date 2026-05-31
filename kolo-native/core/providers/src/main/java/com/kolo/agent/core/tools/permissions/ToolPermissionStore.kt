package com.kolo.agent.core.tools.permissions

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.model.ToolPermissionMode
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

/**
 * Persists per-tool permission modes via DataStore.
 * Safe defaults: alwaysAllow; sensitive/dangerous: askEveryTime.
 */
class ToolPermissionStore @Inject constructor(@ApplicationContext private val applicationContext: Context) {

    private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "kolo_tool_perms")

    private fun keyFor(toolName: String) = stringPreferencesKey("perm_$toolName")

    /** Observe the current permission mode for a tool. Falls back to safe defaults. */
    fun getMode(toolName: String, permission: ToolPermission): Flow<ToolPermissionMode> =
        applicationContext.dataStore.data.map { prefs ->
            val stored = prefs[keyFor(toolName)]
            if (stored != null) {
                try { ToolPermissionMode.valueOf(stored) } catch (_: Exception) { defaultMode(permission) }
            } else {
                defaultMode(permission)
            }
        }

    /** Set the permission mode for a tool. */
    suspend fun setMode(toolName: String, mode: ToolPermissionMode) {
        applicationContext.dataStore.edit { prefs ->
            prefs[keyFor(toolName)] = mode.name
        }
    }

    /** Get all stored permission overrides. */
    fun allOverrides(): Flow<Map<String, ToolPermissionMode>> =
        applicationContext.dataStore.data.map { prefs ->
            prefs.asMap().entries
                .filter { it.key.name.startsWith("perm_") }
                .associate { entry ->
                    val toolName = entry.key.name.removePrefix("perm_")
                    val mode = try { ToolPermissionMode.valueOf(entry.value.toString()) } catch (_: Exception) { ToolPermissionMode.askEveryTime }
                    toolName to mode
                }
        }

    /** Reset a tool's permission to its default. */
    suspend fun resetMode(toolName: String) {
        applicationContext.dataStore.edit { prefs -> prefs.remove(keyFor(toolName)) }
    }

    companion object {
        fun defaultMode(permission: ToolPermission): ToolPermissionMode = when (permission) {
            ToolPermission.safe -> ToolPermissionMode.alwaysAllow
            ToolPermission.sensitive -> ToolPermissionMode.askEveryTime
            ToolPermission.dangerous -> ToolPermissionMode.askEveryTime
        }

        fun canAutoApprove(mode: ToolPermissionMode): Boolean =
            mode == ToolPermissionMode.alwaysAllow

        fun isBlocked(mode: ToolPermissionMode): Boolean =
            mode == ToolPermissionMode.neverAllow
    }
}