package com.kolo.agent.core.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import com.kolo.agent.core.model.CustomToolDef
import com.kolo.agent.core.model.Skill
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
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

    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }

    private val KEY_THEME = stringPreferencesKey("theme_mode")
    private val KEY_DEFAULT_CHAT_FOLDER = stringPreferencesKey("default_chat_folder")
    private val KEY_LOCAL_LLAMA_MODEL_PATH = stringPreferencesKey("local_llama_model_path")
    private val KEY_LOCAL_LLAMA_GPU_LAYERS = intPreferencesKey("local_llama_gpu_layers")
    private val KEY_CUSTOM_INSTRUCTIONS = stringPreferencesKey("custom_instructions")
    private val KEY_CUSTOM_TOOLS = stringPreferencesKey("custom_tools_v1")
    private val KEY_SKILLS = stringPreferencesKey("skills_v1")

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

    val localLlamaModelPath: Flow<String?> = dataStore.data.map { prefs ->
        prefs[KEY_LOCAL_LLAMA_MODEL_PATH]
    }

    suspend fun setLocalLlamaModelPath(modelPath: String?) {
        dataStore.edit { prefs ->
            val cleanPath = modelPath?.trim().orEmpty()
            if (cleanPath.isNotEmpty()) prefs[KEY_LOCAL_LLAMA_MODEL_PATH] = cleanPath
            else prefs.remove(KEY_LOCAL_LLAMA_MODEL_PATH)
        }
    }

    val localLlamaGpuLayers: Flow<Int> = dataStore.data.map { prefs ->
        prefs[KEY_LOCAL_LLAMA_GPU_LAYERS] ?: 0
    }

    suspend fun setLocalLlamaGpuLayers(gpuLayers: Int) {
        dataStore.edit { prefs ->
            prefs[KEY_LOCAL_LLAMA_GPU_LAYERS] = gpuLayers.coerceIn(0, 999)
        }
    }

    val customInstructions: Flow<String> = dataStore.data.map { prefs ->
        prefs[KEY_CUSTOM_INSTRUCTIONS].orEmpty()
    }

    suspend fun setCustomInstructions(value: String) {
        dataStore.edit { prefs ->
            val cleanValue = value.trim()
            if (cleanValue.isNotEmpty()) prefs[KEY_CUSTOM_INSTRUCTIONS] = cleanValue
            else prefs.remove(KEY_CUSTOM_INSTRUCTIONS)
        }
    }

    val customTools: Flow<List<CustomToolDef>> = dataStore.data.map { prefs ->
        decodeList(prefs[KEY_CUSTOM_TOOLS], CustomToolDef.serializer())
    }

    suspend fun saveCustomTool(tool: CustomToolDef) {
        dataStore.edit { prefs ->
            val tools = decodeList(prefs[KEY_CUSTOM_TOOLS], CustomToolDef.serializer()).toMutableList()
            val normalized = tool.copy(updatedAt = System.currentTimeMillis())
            val index = tools.indexOfFirst { it.id == tool.id || it.name == tool.name }
            if (index >= 0) tools[index] = normalized else tools.add(normalized)
            prefs[KEY_CUSTOM_TOOLS] = json.encodeToString(ListSerializer(CustomToolDef.serializer()), tools)
        }
    }

    suspend fun deleteCustomTool(id: String) {
        dataStore.edit { prefs ->
            val tools = decodeList(prefs[KEY_CUSTOM_TOOLS], CustomToolDef.serializer())
                .filterNot { it.id.value == id }
            if (tools.isEmpty()) prefs.remove(KEY_CUSTOM_TOOLS)
            else prefs[KEY_CUSTOM_TOOLS] = json.encodeToString(ListSerializer(CustomToolDef.serializer()), tools)
        }
    }

    val skills: Flow<List<Skill>> = dataStore.data.map { prefs ->
        decodeList(prefs[KEY_SKILLS], Skill.serializer())
    }

    suspend fun saveSkill(skill: Skill) {
        dataStore.edit { prefs ->
            val skills = decodeList(prefs[KEY_SKILLS], Skill.serializer()).toMutableList()
            val normalized = skill.copy(updatedAt = System.currentTimeMillis())
            val index = skills.indexOfFirst { it.id == skill.id || it.name == skill.name }
            if (index >= 0) skills[index] = normalized else skills.add(normalized)
            prefs[KEY_SKILLS] = json.encodeToString(ListSerializer(Skill.serializer()), skills)
        }
    }

    suspend fun deleteSkill(id: String) {
        dataStore.edit { prefs ->
            val skills = decodeList(prefs[KEY_SKILLS], Skill.serializer())
                .filterNot { it.id.value == id }
            if (skills.isEmpty()) prefs.remove(KEY_SKILLS)
            else prefs[KEY_SKILLS] = json.encodeToString(ListSerializer(Skill.serializer()), skills)
        }
    }

    suspend fun setSkillEnabled(id: String, enabled: Boolean) {
        dataStore.edit { prefs ->
            val skills = decodeList(prefs[KEY_SKILLS], Skill.serializer()).map {
                if (it.id.value == id) it.copy(isEnabled = enabled, updatedAt = System.currentTimeMillis()) else it
            }
            if (skills.isEmpty()) prefs.remove(KEY_SKILLS)
            else prefs[KEY_SKILLS] = json.encodeToString(ListSerializer(Skill.serializer()), skills)
        }
    }

    private fun <T> decodeList(raw: String?, serializer: kotlinx.serialization.KSerializer<T>): List<T> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            json.decodeFromString(ListSerializer(serializer), raw)
        } catch (_: Exception) {
            emptyList()
        }
    }
}
