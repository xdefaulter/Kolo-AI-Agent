package com.kolo.agent.core.providers

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import com.kolo.agent.core.model.*
import com.kolo.agent.core.providers.secure.SecureKeyStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

/**
 * Repository for provider configurations backed by DataStore + encrypted storage.
 *
 * API keys are never stored in DataStore — they live in EncryptedSharedPreferences
 * and are loaded into [ProviderConfigKeyStore] on read so that the networking
 * layer can look them up by provider ID.
 */
class ProviderRepository(
    private val context: Context,
    val secureKeyStore: SecureKeyStore,
) {
    private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "kolo_providers")
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true }

    private val PROVIDERS_KEY = stringPreferencesKey("providers_v2")

    /** Get API key for a provider from secure storage + in-memory cache. */
    fun getApiKey(providerId: String): String = ProviderConfigKeyStore[providerId]

    val providersFlow: Flow<List<ProviderConfig>> = context.dataStore.data.map { prefs ->
        decodeProviders(prefs[PROVIDERS_KEY])
    }

    val activeProviderFlow: Flow<ProviderConfig?> = providersFlow.map { providers ->
        providers.firstOrNull { it.isActive }
    }

    suspend fun getAllProviders(): List<ProviderConfig> {
        val prefs = context.dataStore.data.first()
        return decodeProviders(prefs[PROVIDERS_KEY])
    }

    private fun decodeProviders(raw: String?): List<ProviderConfig> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val list = json.decodeFromString<List<ProviderConfig>>(raw)
            // Re-attach API keys from secure storage into the in-memory store
            list.map { config ->
                val key = secureKeyStore.getApiKey(config.id.value) ?: ""
                ProviderConfigKeyStore[config.id.value] = key
                config
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun getActiveProvider(): ProviderConfig? {
        return getAllProviders().firstOrNull { it.isActive }
    }

    suspend fun saveProvider(provider: ProviderConfig, apiKey: String) {
        // Save API key in encrypted storage + in-memory store
        if (apiKey.isNotBlank()) {
            secureKeyStore.saveApiKey(provider.id.value, apiKey)
            ProviderConfigKeyStore[provider.id.value] = apiKey
        } else {
            secureKeyStore.deleteApiKey(provider.id.value)
            ProviderConfigKeyStore.remove(provider.id.value)
        }
        // Serialize config (without key) — keys live in secure storage only
        val providers = getAllProviders().toMutableList()
        val idx = providers.indexOfFirst { it.id == provider.id }
        if (idx >= 0) providers[idx] = provider else providers.add(provider)
        val normalized = if (provider.isActive) {
            providers.map { it.copy(isActive = it.id == provider.id) }
        } else {
            providers
        }
        writeProviders(normalized)
    }

    suspend fun deleteProvider(id: ProviderId) {
        secureKeyStore.deleteApiKey(id.value)
        ProviderConfigKeyStore.remove(id.value)
        val providers = getAllProviders().filter { it.id != id }
        writeProviders(providers)
    }

    suspend fun setActiveProvider(id: ProviderId) {
        val providers = getAllProviders().map { config ->
            config.copy(isActive = config.id == id)
        }
        writeProviders(providers)
    }

    suspend fun setActiveModel(providerId: ProviderId, modelId: String) {
        val providers = getAllProviders().map { config ->
            if (config.id != providerId) {
                config
            } else {
                config.copy(
                    models = config.models.map { model ->
                        model.copy(isActive = model.modelId == modelId)
                    },
                    updatedAt = System.currentTimeMillis(),
                )
            }
        }
        writeProviders(providers)
    }

    private suspend fun writeProviders(providers: List<ProviderConfig>) {
        val serialized = json.encodeToString(
            kotlinx.serialization.builtins.ListSerializer(ProviderConfig.serializer()),
            providers,
        )
        context.dataStore.edit { prefs ->
            prefs[PROVIDERS_KEY] = serialized
        }
    }
}
