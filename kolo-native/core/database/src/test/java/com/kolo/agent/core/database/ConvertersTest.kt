package com.kolo.agent.core.database

import com.kolo.agent.core.model.ChatId
import com.kolo.agent.core.model.FolderId
import com.kolo.agent.core.model.MemoryId
import com.kolo.agent.core.model.MessageId
import com.kolo.agent.core.model.MessageRole
import com.kolo.agent.core.model.MessageStatus
import com.kolo.agent.core.model.ProviderId
import com.kolo.agent.core.model.TemplateId
import com.kolo.agent.core.model.ToolCallInfo
import org.junit.Assert.*
import org.junit.Test

class ConvertersTest {

    private val converters = Converters()

    // ---------------------------------------------------------------------
    // String list converters
    // ---------------------------------------------------------------------

    @Test
    fun toStringListParsesCommaSeparatedValues() {
        val result = converters.toStringList("a,b,c")
        assertEquals(listOf("a", "b", "c"), result)
    }

    @Test
    fun toStringListReturnsNullForNullInput() {
        assertNull(converters.toStringList(null))
    }

    @Test
    fun toStringListReturnsNullForEmptyString() {
        // isNotBlank() filters out "" and whitespace-only strings.
        assertNull(converters.toStringList(""))
    }

    @Test
    fun toStringListReturnsNullForBlankString() {
        assertNull(converters.toStringList("   "))
    }

    @Test
    fun toStringListHandlesSingleElement() {
        assertEquals(listOf("only"), converters.toStringList("only"))
    }

    @Test
    fun toStringListTrimsWhitespaceAroundElements() {
        val result = converters.toStringList(" one , two , three ")
        assertEquals(listOf("one", "two", "three"), result)
    }

    @Test
    fun toStringListDropsEntriesThatBecomeEmptyAfterSplit() {
        // "a,,b" splits into ["a", "", "b"]; empty entries are filtered out.
        assertEquals(listOf("a", "b"), converters.toStringList("a,,b"))
    }

    @Test
    fun fromStringListJoinsWithComma() {
        assertEquals("a,b,c", converters.fromStringList(listOf("a", "b", "c")))
    }

    @Test
    fun fromStringListReturnsNullForNullInput() {
        assertNull(converters.fromStringList(null))
    }

    @Test
    fun stringListRoundTripPreservesNonEmptyValues() {
        val original = listOf("alpha", "beta", "gamma")
        val encoded = converters.fromStringList(original)
        val decoded = converters.toStringList(encoded)
        assertEquals(original, decoded)
    }

    @Test
    fun stringListRoundTripDoesNotPreserveBlankEntries() {
        // Blank entries survive encoding ("a,,b") but are dropped on decode,
        // because the decoder filters out empty splits.
        val original = listOf("a", "", "b")
        val decoded = converters.toStringList(converters.fromStringList(original))
        assertEquals(listOf("a", "b"), decoded)
    }

    // ---------------------------------------------------------------------
    // ToolCall list converters
    // ---------------------------------------------------------------------

    @Test
    fun toToolCallListParsesValidJsonArray() {
        val json = """[{"id":"call_1","name":"search","arguments":"{\"q\":\"hi\"}"}]"""
        val result = converters.toToolCallList(json)
        assertNotNull(result)
        assertEquals(1, result!!.size)
        assertEquals("call_1", result[0].id)
        assertEquals("search", result[0].name)
    }

    @Test
    fun toToolCallListReturnsNullForNullInput() {
        assertNull(converters.toToolCallList(null))
    }

    @Test
    fun toToolCallListReturnsNullForMalformedJson() {
        // runCatching{}.getOrNull() silently swallows the deserialization
        // failure and returns null. This test pins that (questionable)
        // behaviour so any future change is deliberate.
        assertNull(converters.toToolCallList("not valid json ["))
    }

    @Test
    fun toToolCallListReturnsNullForJsonObjectInsteadOfArray() {
        // The decoder expects a JSON array; a bare object is malformed for
        // ListSerializer and must yield null rather than throw.
        assertNull(converters.toToolCallList("""{"id":"x","name":"y","arguments":"{}"}"""))
    }

    @Test
    fun toToolCallListReturnsEmptyListForEmptyArray() {
        assertEquals(emptyList<ToolCallInfo>(), converters.toToolCallList("[]"))
    }

    @Test
    fun toToolCallListIgnoresUnknownKeys() {
        // The decoder is configured with ignoreUnknownKeys = true, so extra
        // fields must not cause a null result.
        val json = """[{"id":"c1","name":"n","arguments":"{}","extra":"ignored"}]"""
        val result = converters.toToolCallList(json)
        assertNotNull(result)
        assertEquals(1, result!!.size)
        assertEquals("c1", result[0].id)
    }

    @Test
    fun fromToolCallListSerializesNonNullList() {
        val calls = listOf(ToolCallInfo(id = "call_1", name = "search", arguments = """{"q":"hi"}"""))
        val encoded = converters.fromToolCallList(calls)
        assertNotNull(encoded)
        // Decode it back and confirm equality — round-trip via the same serializer.
        val decoded = converters.toToolCallList(encoded)
        assertEquals(calls, decoded)
    }

    @Test
    fun fromToolCallListSerializesEmptyList() {
        val encoded = converters.fromToolCallList(emptyList())
        assertNotNull(encoded)
        assertEquals(emptyList<ToolCallInfo>(), converters.toToolCallList(encoded))
    }

    @Test
    fun fromToolCallListReturnsNullForNullInput() {
        assertNull(converters.fromToolCallList(null))
    }

    @Test
    fun toolCallListRoundTripPreservesMultipleEntries() {
        val calls = listOf(
            ToolCallInfo(id = "1", name = "alpha", arguments = "{}"),
            ToolCallInfo(id = "2", name = "beta", arguments = """{"k":1}"""),
        )
        val decoded = converters.toToolCallList(converters.fromToolCallList(calls))
        assertEquals(calls, decoded)
    }

    // ---------------------------------------------------------------------
    // Identifier converters (round-trip)
    // ---------------------------------------------------------------------

    @Test
    fun chatIdRoundTrip() {
        val id = ChatId("chat-123")
        assertEquals("chat-123", converters.fromChatId(id))
        assertEquals(id, converters.toChatId("chat-123"))
    }

    @Test
    fun chatIdNullRoundTrip() {
        assertNull(converters.fromChatId(null))
        assertNull(converters.toChatId(null))
    }

    @Test
    fun messageIdRoundTrip() {
        val id = MessageId("msg-1")
        assertEquals("msg-1", converters.fromMessageId(id))
        assertEquals(id, converters.toMessageId("msg-1"))
    }

    @Test
    fun messageIdNullRoundTrip() {
        assertNull(converters.fromMessageId(null))
        assertNull(converters.toMessageId(null))
    }

    @Test
    fun providerIdRoundTrip() {
        val id = ProviderId("prov-1")
        assertEquals("prov-1", converters.fromProviderId(id))
        assertEquals(id, converters.toProviderId("prov-1"))
    }

    @Test
    fun providerIdNullRoundTrip() {
        assertNull(converters.fromProviderId(null))
        assertNull(converters.toProviderId(null))
    }

    @Test
    fun folderIdRoundTrip() {
        val id = FolderId("folder-1")
        assertEquals("folder-1", converters.fromFolderId(id))
        assertEquals(id, converters.toFolderId("folder-1"))
    }

    @Test
    fun folderIdNullRoundTrip() {
        assertNull(converters.fromFolderId(null))
        assertNull(converters.toFolderId(null))
    }

    @Test
    fun templateIdRoundTrip() {
        val id = TemplateId("tmpl-1")
        assertEquals("tmpl-1", converters.fromTemplateId(id))
        assertEquals(id, converters.toTemplateId("tmpl-1"))
    }

    @Test
    fun templateIdNullRoundTrip() {
        assertNull(converters.fromTemplateId(null))
        assertNull(converters.toTemplateId(null))
    }

    @Test
    fun memoryIdRoundTrip() {
        val id = MemoryId("mem-1")
        assertEquals("mem-1", converters.fromMemoryId(id))
        assertEquals(id, converters.toMemoryId("mem-1"))
    }

    @Test
    fun memoryIdNullRoundTrip() {
        assertNull(converters.fromMemoryId(null))
        assertNull(converters.toMemoryId(null))
    }

    // ---------------------------------------------------------------------
    // Enum converters
    // ---------------------------------------------------------------------

    @Test
    fun messageRoleRoundTrip() {
        for (role in MessageRole.entries) {
            val wire = converters.fromMessageRole(role)
            assertEquals(role.wire, wire)
            assertEquals(role, converters.toMessageRole(wire))
        }
    }

    @Test
    fun toMessageRoleDefaultsToUserForUnknownWireValue() {
        // toMessageRole delegates to MessageRole.fromWire, which defaults to
        // user for any unrecognized value rather than throwing.
        assertEquals(MessageRole.user, converters.toMessageRole("does-not-exist"))
    }

    @Test
    fun messageStatusRoundTrip() {
        for (status in MessageStatus.entries) {
            val wire = converters.fromMessageStatus(status)
            assertEquals(status.name, wire)
            assertEquals(status, converters.toMessageStatus(wire))
        }
    }

    @Test
    fun toMessageStatusReturnsNullForNullInput() {
        assertNull(converters.toMessageStatus(null))
    }

    @Test
    fun toMessageStatusReturnsNullForUnknownValue() {
        assertNull(converters.toMessageStatus("not-a-status"))
    }
}
