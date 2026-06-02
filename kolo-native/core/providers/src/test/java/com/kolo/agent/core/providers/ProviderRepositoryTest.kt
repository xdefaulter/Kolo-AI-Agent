package com.kolo.agent.core.providers

import com.kolo.agent.core.model.ProviderConfig
import org.junit.Assert.assertEquals
import org.junit.Test

class ProviderRepositoryTest {
    @Test
    fun normalizeActiveProviders_marksFirstProviderActiveWhenNoneAreActive() {
        val providers = listOf(
            provider("openai", isActive = false),
            provider("ollama", isActive = false),
        )

        val normalized = ProviderRepository.normalizeActiveProviders(providers)

        assertEquals(listOf(true, false), normalized.map { it.isActive })
    }

    @Test
    fun normalizeActiveProviders_keepsExistingActiveProvider() {
        val providers = listOf(
            provider("openai", isActive = false),
            provider("ollama", isActive = true),
        )

        val normalized = ProviderRepository.normalizeActiveProviders(providers)

        assertEquals(listOf(false, true), normalized.map { it.isActive })
    }

    @Test
    fun normalizeActiveProviders_allowsOnlyOneActiveProvider() {
        val providers = listOf(
            provider("openai", isActive = true),
            provider("ollama", isActive = true),
        )

        val normalized = ProviderRepository.normalizeActiveProviders(providers)

        assertEquals(listOf(true, false), normalized.map { it.isActive })
    }

    private fun provider(name: String, isActive: Boolean): ProviderConfig =
        ProviderConfig(
            name = name,
            baseUrl = "https://example.test/$name",
            isActive = isActive,
        )
}
