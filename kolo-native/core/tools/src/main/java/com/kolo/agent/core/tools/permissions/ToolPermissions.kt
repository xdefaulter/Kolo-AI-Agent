package com.kolo.agent.core.tools.permissions

import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.model.ToolPermissionMode

/**
 * Manages per-tool permission settings.
 * Persists to DataStore.
 */
data class ToolPermissionEntry(
    val toolName: String,
    val level: ToolPermission,
    val mode: ToolPermissionMode = when (level) {
        ToolPermission.safe -> ToolPermissionMode.alwaysAllow
        ToolPermission.sensitive -> ToolPermissionMode.askEveryTime
        ToolPermission.dangerous -> ToolPermissionMode.askEveryTime
    },
)

object DefaultPermissions {
    fun defaultMode(permission: ToolPermission): ToolPermissionMode = when (permission) {
        ToolPermission.safe -> ToolPermissionMode.alwaysAllow
        ToolPermission.sensitive -> ToolPermissionMode.askEveryTime
        ToolPermission.dangerous -> ToolPermissionMode.askEveryTime
    }

    fun canAutoApprove(entry: ToolPermissionEntry): Boolean =
        entry.mode == ToolPermissionMode.alwaysAllow

    fun isBlocked(entry: ToolPermissionEntry): Boolean =
        entry.mode == ToolPermissionMode.neverAllow
}