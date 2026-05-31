package com.kolo.agent.core.providers

/**
 * In-memory companion store for API keys.
 * ProviderConfig is a serializable data class — we don't want
 * API keys in its serialized form. This store holds keys in memory
 * so they can be looked up by provider ID at runtime.
 */
object ProviderConfigKeyStore {
    private val store = mutableMapOf<String, String>()

    operator fun get(id: String): String = store[id] ?: ""
    operator fun set(id: String, value: String) { store[id] = value }
    fun remove(id: String) { store.remove(id) }
    fun clear() { store.clear() }
}