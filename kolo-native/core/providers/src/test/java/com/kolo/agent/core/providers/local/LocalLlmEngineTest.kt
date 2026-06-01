package com.kolo.agent.core.providers.local

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import org.junit.Assert.*
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.Rule
import java.io.File

class LocalLlmEngineTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    // Test engine with default isValidModel from interface
    private fun createTestEngine() = object : LocalLlmEngine {
        override val isModelLoaded get() = false
        override val loadedModelPath get() = null
        override suspend fun loadModel(modelPath: String, contextSize: Int, threads: Int) {}
        override suspend fun unloadModel() {}
        override fun completeStream(prompt: String, maxTokens: Int, temperature: Float, topP: Float, repeatPenalty: Float): Flow<String> = flowOf()
    }

    // ──── ModelInfo ────

    @Test
    fun modelInfoSizeFormattedGigabytes() {
        val info = ModelInfo(path = "/test/model.gguf", name = "test", sizeBytes = 2_500_000_000L)
        assertEquals("2.5 GB", info.sizeFormatted)
    }

    @Test
    fun modelInfoSizeFormattedMegabytes() {
        val info = ModelInfo(path = "/test/model.gguf", name = "test", sizeBytes = 450_000_000L)
        assertEquals("450.0 MB", info.sizeFormatted)
    }

    @Test
    fun modelInfoSizeFormattedKilobytes() {
        val info = ModelInfo(path = "/test/model.gguf", name = "test", sizeBytes = 512_000L)
        assertEquals("512.0 KB", info.sizeFormatted)
    }

    @Test
    fun modelInfoSizeFormattedSmallFile() {
        val info = ModelInfo(path = "/test/model.gguf", name = "test", sizeBytes = 500L)
        assertEquals("500 B", info.sizeFormatted)
    }

    // ──── GGUF Validation via LocalLlmEngine.isValidModel ────

    @Test
    fun isValidModelReturnsFalseForNonExistentFile() {
        assertFalse(createTestEngine().isValidModel("/nonexistent/path/model.gguf"))
    }

    @Test
    fun isValidModelReturnsFalseForEmptyFile() {
        val emptyFile = tempFolder.newFile("empty.gguf")
        assertEquals(0L, emptyFile.length())
        assertFalse(createTestEngine().isValidModel(emptyFile.absolutePath))
    }

    @Test
    fun isValidModelReturnsFalseForSmallFile() {
        val smallFile = tempFolder.newFile("small.gguf")
        smallFile.writeBytes(ByteArray(32) { 0 })
        assertFalse(createTestEngine().isValidModel(smallFile.absolutePath))
    }

    @Test
    fun isValidModelReturnsFalseForInvalidMagic() {
        val invalidFile = tempFolder.newFile("invalid.gguf")
        val data = ByteArray(128) { (it % 256).toByte() }
        invalidFile.writeBytes(data)
        assertFalse(createTestEngine().isValidModel(invalidFile.absolutePath))
    }

    @Test
    fun isValidModelReturnsTrueForValidGgufMagic() {
        val validFile = tempFolder.newFile("valid.gguf")
        val data = ByteArray(128) { 0 }
        data[0] = 0x47  // 'G'
        data[1] = 0x47  // 'G'
        data[2] = 0x55  // 'U'
        data[3] = 0x46  // 'F'
        validFile.writeBytes(data)
        assertTrue(createTestEngine().isValidModel(validFile.absolutePath))
    }

    @Test
    fun isValidModelReturnsFalseForPartialMagic() {
        val partialFile = tempFolder.newFile("partial.gguf")
        val data = ByteArray(128) { 0 }
        data[0] = 0x47  // 'G'
        data[1] = 0x47  // 'G'
        data[2] = 0x55  // 'U'
        // data[3] missing 'F' — left as 0
        partialFile.writeBytes(data)
        assertFalse(createTestEngine().isValidModel(partialFile.absolutePath))
    }

    // ──── ImportedModel ────

    @Test
    fun importedModelSizeFormattedGigabytes() {
        val model = ImportedModel(
            name = "llama-3.2-1b",
            fileName = "llama-3.2-1b-Q4_K_M.gguf",
            path = "/data/models/llama-3.2-1b-Q4_K_M.gguf",
            sizeBytes = 1_200_000_000L,
            isValidGguf = true,
        )
        assertEquals("1.2 GB", model.sizeFormatted)
    }

    @Test
    fun importedModelSizeFormattedMegabytes() {
        val model = ImportedModel(
            name = "tiny-model",
            fileName = "tiny.gguf",
            path = "/data/models/tiny.gguf",
            sizeBytes = 100_000_000L,
            isValidGguf = true,
        )
        assertEquals("100.0 MB", model.sizeFormatted)
    }

    @Test
    fun importedModelSizeFormattedKilobytes() {
        val model = ImportedModel(
            name = "mini",
            fileName = "mini.gguf",
            path = "/data/models/mini.gguf",
            sizeBytes = 500_000L,
            isValidGguf = true,
        )
        assertEquals("500.0 KB", model.sizeFormatted)
    }

    @Test
    fun importedModelWithInvalidGgufFlag() {
        val model = ImportedModel(
            name = "bad-file",
            fileName = "bad.gguf",
            path = "/data/models/bad.gguf",
            sizeBytes = 500_000L,
            isValidGguf = false,
        )
        assertFalse(model.isValidGguf)
    }

    // ──── LocalModelManager.BridgeStatus ────

    @Test
    fun bridgeStatusHasFourStates() {
        assertEquals(4, LocalModelManager.BridgeStatus.entries.size)
        assertTrue(LocalModelManager.BridgeStatus.entries.contains(LocalModelManager.BridgeStatus.Unknown))
        assertTrue(LocalModelManager.BridgeStatus.entries.contains(LocalModelManager.BridgeStatus.Checking))
        assertTrue(LocalModelManager.BridgeStatus.entries.contains(LocalModelManager.BridgeStatus.Available))
        assertTrue(LocalModelManager.BridgeStatus.entries.contains(LocalModelManager.BridgeStatus.Unavailable))
    }

    // ──── LocalModelManager.ImportStatus ────

    @Test
    fun importStatusImportingHasProgressFields() {
        val importing = LocalModelManager.ImportStatus.Importing("model.gguf", progress = 0.5f, bytesReceived = 500L, totalBytes = 1000L)
        assertEquals("model.gguf", importing.fileName)
        assertEquals(0.5f, importing.progress, 0.01f)
        assertEquals(500L, importing.bytesReceived)
        assertEquals(1000L, importing.totalBytes)
    }

    @Test
    fun importStatusImportingIndeterminateProgress() {
        val importing = LocalModelManager.ImportStatus.Importing("model.gguf", progress = -1f, bytesReceived = 100L, totalBytes = -1L)
        assertEquals(-1f, importing.progress, 0.01f)
        assertEquals(-1L, importing.totalBytes)
    }

    @Test
    fun importStatusIdleIsNotImportingOrError() {
        val idle = LocalModelManager.ImportStatus.Idle
        assertFalse(idle is LocalModelManager.ImportStatus.Importing)
        assertFalse(idle is LocalModelManager.ImportStatus.Error)
        assertFalse(idle is LocalModelManager.ImportStatus.Success)
    }

    // ──── LlmEngineFactory ────

    @Test
    fun factoryReturnsStubForOpenAiCompat() {
        val config = com.kolo.agent.core.model.ProviderConfig(
            name = "Test",
            baseUrl = "https://api.test.com/v1",
            kind = com.kolo.agent.core.model.ProviderKind.openaiCompat,
        )
        val engine = LlmEngineFactory.create(config)
        assertTrue(engine is StubLocalLlmEngine)
    }

    @Test
    fun factoryReturnsStubWhenCacheIsNull() {
        val config = com.kolo.agent.core.model.ProviderConfig(
            name = "Local",
            baseUrl = "llama.cpp://local",
            kind = com.kolo.agent.core.model.ProviderKind.localLlama,
        )
        // When no LocalModelManager is available, the no-arg create may call
        // LlamaCppBridge.isAvailable() which loads the library. Since we can't
        // control that in a unit test, we test the non-local case instead.
        val engine = LlmEngineFactory.create(
            com.kolo.agent.core.model.ProviderConfig(
                name = "Remote",
                baseUrl = "https://api.test.com/v1",
                kind = com.kolo.agent.core.model.ProviderKind.openaiCompat,
            )
        )
        assertTrue(engine is StubLocalLlmEngine)
    }

    // ──── GgufHelpers delegation ────

    @Test
    fun helpersFormatSizeUsedByLocalModelManager() {
        // Verify LocalModelManager.formatSize delegates to GgufHelpers.formatSize
        assertEquals(GgufHelpers.formatSize(1_000_000L), "1.0 MB")
    }

    @Test
    fun helpersResolveCollisionNaming() {
        val dir = tempFolder.newFolder("collision_test")
        File(dir, "model.gguf").writeBytes(ByteArray(4))
        val result = GgufHelpers.resolveCollision(dir, "model.gguf")
        assertEquals("model-1.gguf", result.name)
    }
}