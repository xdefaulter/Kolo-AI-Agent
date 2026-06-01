package com.kolo.agent.core.providers.local

import org.junit.Assert.*
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.Rule
import java.io.File
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * Unit tests for GGUF file format validation logic.
 *
 * GGUF files start with the 4-byte magic: 0x47 0x47 0x55 0x46 ("GGUF").
 * Tests both the pure [GgufHelpers] and the [LocalLlmEngine.isValidModel] path.
 */
class GgufValidationTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private fun createFile(name: String, content: ByteArray): File {
        val file = tempFolder.newFile(name)
        file.writeBytes(content)
        return file
    }

    private fun createTestEngine() = object : LocalLlmEngine {
        override val isModelLoaded get() = false
        override val loadedModelPath get() = null
        override suspend fun loadModel(modelPath: String, contextSize: Int, threads: Int) {}
        override suspend fun unloadModel() {}
        override fun completeStream(prompt: String, maxTokens: Int, temperature: Float, topP: Float, repeatPenalty: Float): Flow<String> = flowOf()
    }

    // ──── GgufHelpers — pure validation ────

    @Test
    fun ggufMagicBytesAreCorrect() {
        assertArrayEquals(byteArrayOf(0x47, 0x47, 0x55, 0x46), GgufHelpers.GGUF_MAGIC)
    }

    @Test
    fun ggufMagicEqualsAsciiGGUF() {
        assertEquals("GGUF", String(GgufHelpers.GGUF_MAGIC, Charsets.US_ASCII))
    }

    @Test
    fun ggufMagicBytesAreExactly4Bytes() {
        assertEquals(4, GgufHelpers.GGUF_MAGIC.size)
    }

    @Test
    fun helperValidationValidFile() {
        val data = ByteArray(128) { 0 }
        data[0] = 0x47.toByte()  // G
        data[1] = 0x47.toByte()  // G
        data[2] = 0x55.toByte()  // U
        data[3] = 0x46.toByte()  // F
        val file = createFile("valid.gguf", data)
        assertTrue(GgufHelpers.validateGgufMagic(file))
    }

    @Test
    fun helperValidationInvalidMagic() {
        val data = ByteArray(128) { 0 }
        data[0] = 0x89.toByte()
        data[1] = 0x50.toByte()
        data[2] = 0x4E.toByte()
        data[3] = 0x47.toByte()
        val file = createFile("not-gguf.gguf", data)
        assertFalse(GgufHelpers.validateGgufMagic(file))
    }

    @Test
    fun helperValidationEmptyFile() {
        val file = createFile("empty.gguf", ByteArray(0))
        assertFalse(GgufHelpers.validateGgufMagic(file))
    }

    @Test
    fun helperValidationNonExistentFile() {
        assertFalse(GgufHelpers.validateGgufMagic(File("/nonexistent/path/model.gguf")))
    }

    @Test
    fun helperIsValidModelRejectsSmallFile() {
        val file = createFile("small.gguf", ByteArray(32) { 0x47.toByte() })
        assertFalse(GgufHelpers.isValidModel(file.absolutePath))
    }

    @Test
    fun helperIsValidModelAcceptsValidGguf() {
        val data = ByteArray(128) { 0 }
        data[0] = 0x47.toByte()
        data[1] = 0x47.toByte()
        data[2] = 0x55.toByte()
        data[3] = 0x46.toByte()
        val file = createFile("valid.gguf", data)
        assertTrue(GgufHelpers.isValidModel(file.absolutePath))
    }

    @Test
    fun helperIsValidModelRejectsNonExistentPath() {
        assertFalse(GgufHelpers.isValidModel("/nonexistent/model.gguf"))
    }

    // ──── GgufHelpers — formatSize ────

    @Test
    fun formatSizeGigabytes() {
        assertEquals("2.5 GB", GgufHelpers.formatSize(2_500_000_000L))
    }

    @Test
    fun formatSizeMegabytes() {
        assertEquals("450.0 MB", GgufHelpers.formatSize(450_000_000L))
    }

    @Test
    fun formatSizeKilobytes() {
        assertEquals("512.0 KB", GgufHelpers.formatSize(512_000L))
    }

    @Test
    fun formatSizeBytes() {
        assertEquals("500 B", GgufHelpers.formatSize(500L))
    }

    // ──── GgufHelpers — resolveCollision ────

    @Test
    fun resolveCollisionNoConflict() {
        val dir = tempFolder.newFolder("col1")
        val result = GgufHelpers.resolveCollision(dir, "model.gguf")
        assertEquals("model.gguf", result.name)
    }

    @Test
    fun resolveCollisionOneExisting() {
        val dir = tempFolder.newFolder("col2")
        File(dir, "model.gguf").writeBytes(ByteArray(4))
        val result = GgufHelpers.resolveCollision(dir, "model.gguf")
        assertEquals("model-1.gguf", result.name)
    }

    @Test
    fun resolveCollisionTwoExisting() {
        val dir = tempFolder.newFolder("col3")
        File(dir, "model.gguf").writeBytes(ByteArray(4))
        File(dir, "model-1.gguf").writeBytes(ByteArray(4))
        val result = GgufHelpers.resolveCollision(dir, "model.gguf")
        assertEquals("model-2.gguf", result.name)
    }

    @Test
    fun resolveCollisionNoExtension() {
        val dir = tempFolder.newFolder("col4")
        File(dir, "README").writeBytes(ByteArray(4))
        val result = GgufHelpers.resolveCollision(dir, "README")
        assertEquals("README-1", result.name)
    }

    // ──── GgufHelpers — scanModelsDir ────

    @Test
    fun scanEmptyDir() {
        val dir = tempFolder.newFolder("empty_models")
        val models = GgufHelpers.scanModelsDir(dir)
        assertTrue(models.isEmpty())
    }

    @Test
    fun scanNonExistentDir() {
        val models = GgufHelpers.scanModelsDir(File("/nonexistent/dir"))
        assertTrue(models.isEmpty())
    }

    @Test
    fun scanDirWithModels() {
        val dir = tempFolder.newFolder("models_scan")
        val magic = byteArrayOf(0x47, 0x47, 0x55, 0x46) + ByteArray(124) { 0 }
        File(dir, "model-a.gguf").writeBytes(magic)
        File(dir, "model-b.gguf").writeBytes(magic)
        File(dir, "readme.txt").writeText("not a model")

        val models = GgufHelpers.scanModelsDir(dir)
        assertEquals(2, models.size)
        assertTrue(models.all { it.isValidGguf })
    }

    @Test
    fun scanDirFiltersInvalidGguf() {
        val dir = tempFolder.newFolder("models_invalid")
        val magic = byteArrayOf(0x47, 0x47, 0x55, 0x46) + ByteArray(124) { 0 }
        File(dir, "valid.gguf").writeBytes(magic)
        File(dir, "invalid.gguf").writeBytes(ByteArray(128) { 0 }) // wrong magic

        val models = GgufHelpers.scanModelsDir(dir)
        assertEquals(2, models.size)
        assertEquals(1, models.count { it.isValidGguf })
        assertEquals(1, models.count { !it.isValidGguf })
    }

    // ──── LocalLlmEngine.isValidModel (interface default) ────

    @Test
    fun validGgufMagicBytes() {
        val data = ByteArray(128) { 0 }
        data[0] = 0x47.toByte()  // G
        data[1] = 0x47.toByte()  // G
        data[2] = 0x55.toByte()  // U
        data[3] = 0x46.toByte()  // F
        val file = createFile("valid.gguf", data)
        assertTrue(createTestEngine().isValidModel(file.absolutePath))
    }

    @Test
    fun invalidGgufMagicBytes() {
        val data = ByteArray(128) { 0 }
        data[0] = 0x89.toByte()
        data[1] = 0x50.toByte()
        data[2] = 0x4E.toByte()
        data[3] = 0x47.toByte()
        val file = createFile("not-gguf.gguf", data)
        assertFalse(createTestEngine().isValidModel(file.absolutePath))
    }

    @Test
    fun fileTooShortForMagic() {
        val data = ByteArray(3) { 0x47.toByte() }
        val file = createFile("short.gguf", data)
        assertFalse(createTestEngine().isValidModel(file.absolutePath))
    }

    @Test
    fun emptyFileIsNotValid() {
        val file = createFile("empty.gguf", ByteArray(0))
        assertFalse(createTestEngine().isValidModel(file.absolutePath))
    }

    @Test
    fun nonExistentFileIsNotValid() {
        assertFalse(createTestEngine().isValidModel("/nonexistent/path/model.gguf"))
    }

    // ──── ImportStatus ────

    @Test
    fun importStatusIdleIsNotErrorOrSuccess() {
        val idle = LocalModelManager.ImportStatus.Idle
        assertFalse(idle is LocalModelManager.ImportStatus.Error)
        assertFalse(idle is LocalModelManager.ImportStatus.Success)
        assertFalse(idle is LocalModelManager.ImportStatus.Importing)
    }

    @Test
    fun importStatusErrorHasMessage() {
        val error = LocalModelManager.ImportStatus.Error("test error")
        assertEquals("test error", error.message)
    }

    @Test
    fun importStatusSuccessHasModel() {
        val model = ImportedModel(name = "test", fileName = "test.gguf", path = "/test.gguf", sizeBytes = 100L, isValidGguf = true)
        val success = LocalModelManager.ImportStatus.Success(model)
        assertEquals("test", success.model.name)
    }

    @Test
    fun importStatusImportingHasFileName() {
        val importing = LocalModelManager.ImportStatus.Importing("model.gguf")
        assertEquals("model.gguf", importing.fileName)
        assertEquals(0f, importing.progress, 0.01f)
    }
}