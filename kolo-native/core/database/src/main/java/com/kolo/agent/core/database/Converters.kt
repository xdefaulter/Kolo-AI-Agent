package com.kolo.agent.core.database

import androidx.room.TypeConverter
import com.kolo.agent.core.model.*

class Converters {
    @TypeConverter
    fun fromChatId(id: ChatId?): String? = id?.value

    @TypeConverter
    fun toChatId(value: String?): ChatId? = value?.let(::ChatId)

    @TypeConverter
    fun fromMessageId(id: MessageId?): String? = id?.value

    @TypeConverter
    fun toMessageId(value: String?): MessageId? = value?.let(::MessageId)

    @TypeConverter
    fun fromProviderId(id: ProviderId?): String? = id?.value

    @TypeConverter
    fun toProviderId(value: String?): ProviderId? = value?.let(::ProviderId)

    @TypeConverter
    fun fromFolderId(id: FolderId?): String? = id?.value

    @TypeConverter
    fun toFolderId(value: String?): FolderId? = value?.let(::FolderId)

    @TypeConverter
    fun fromTemplateId(id: TemplateId?): String? = id?.value

    @TypeConverter
    fun toTemplateId(value: String?): TemplateId? = value?.let(::TemplateId)

    @TypeConverter
    fun fromMemoryId(id: MemoryId?): String? = id?.value

    @TypeConverter
    fun toMemoryId(value: String?): MemoryId? = value?.let(::MemoryId)

    @TypeConverter
    fun fromMessageRole(role: MessageRole): String = role.wire

    @TypeConverter
    fun toMessageRole(value: String): MessageRole = MessageRole.fromWire(value)

    @TypeConverter
    fun fromMessageStatus(status: MessageStatus?): String? = status?.name

    @TypeConverter
    fun toMessageStatus(value: String?): MessageStatus? =
        value?.let { MessageStatus.valueOf(it) }

    @TypeConverter
    fun fromToolCallList(calls: List<ToolCallInfo>?): String? =
        calls?.let { kotlinx.serialization.json.Json.encodeToString(listSer, it) }

    @TypeConverter
    fun toToolCallList(value: String?): List<ToolCallInfo>? =
        value?.let { kotlinx.serialization.json.Json.decodeFromString(listSer, it) }

    @TypeConverter
    fun fromStringList(list: List<String>?): String? =
        list?.joinToString(",")

    @TypeConverter
    fun toStringList(value: String?): List<String>? =
        value?.takeIf { it.isNotBlank() }?.split(",")?.filter { it.isNotEmpty() }

    companion object {
        private val listSer = kotlinx.serialization.builtins.ListSerializer(ToolCallInfo.serializer())
    }
}