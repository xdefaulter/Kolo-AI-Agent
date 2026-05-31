package com.kolo.agent.core.model

import kotlinx.serialization.Serializable

/**
 * Unique identifier for a chat conversation.
 */
@Serializable
data class ChatId(val value: String)

/**
 * Unique identifier for a message within a chat.
 */
@Serializable
data class MessageId(val value: String)

/**
 * Unique identifier for a provider configuration.
 */
@Serializable
data class ProviderId(val value: String)

/**
 * Unique identifier for a memory entry.
 */
@Serializable
data class MemoryId(val value: String)

/**
 * Unique identifier for a folder.
 */
@Serializable
data class FolderId(val value: String)

/**
 * Unique identifier for a prompt template.
 */
@Serializable
data class TemplateId(val value: String)

/**
 * Unique identifier for a tool call within a message.
 */
@Serializable
data class ToolCallId(val value: String)

/**
 * Unique identifier for a custom tool definition.
 */
@Serializable
data class CustomToolId(val value: String)

/**
 * Unique identifier for a skill.
 */
@Serializable
data class SkillId(val value: String)