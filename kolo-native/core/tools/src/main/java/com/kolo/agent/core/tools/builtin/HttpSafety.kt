package com.kolo.agent.core.tools.builtin

import java.net.URI

/**
 * Shared URL-safety helpers used by both [HttpGetTool] and [HttpPostTool].
 *
 * These guards prevent the LLM-driven HTTP tools from reaching internal/private
 * network hosts (SSRF mitigation). See [isInternalHost] for the blocklist.
 */
internal fun isInternalHost(host: String): Boolean {
    val lower = host.lowercase()
    if (lower == "localhost") return true
    // Block common internal IP ranges
    val ip = lower.removeSurrounding("[", "]")
    if (ip == "0.0.0.0" || ip == "::" || ip == "::1") return true
    // 127.x.x.x
    if (ip.startsWith("127.")) return true
    // 10.x.x.x
    if (ip.startsWith("10.")) return true
    // 192.168.x.x
    if (ip.startsWith("192.168.")) return true
    // 172.16-31.x.x
    if (ip.startsWith("172.")) {
        val parts = ip.split(".")
        if (parts.size >= 2) {
            val second = parts[1].toIntOrNull()
            if (second != null && second in 16..31) return true
        }
    }
    // 169.254.x.x (link-local / cloud metadata)
    if (ip.startsWith("169.254.")) return true
    // 100.64.0.0/10 (CGNAT)
    if (ip.startsWith("100.")) {
        val parts = ip.split(".")
        if (parts.size >= 2) {
            val second = parts[1].toIntOrNull()
            if (second != null && second in 64..127) return true
        }
    }
    // IPv6 unique local addresses fc00::/7 (ULA) and link-local fe80::/10.
    // Only apply to bracketed or bare IPv6 literals (identified by containing ':'),
    // so hostnames starting with 'fc'/'fd'/'fe' are not wrongly blocked.
    if (ip.contains(':')) {
        // ULA specifically starts with fc or fd
        if (ip.startsWith("fc") || ip.startsWith("fd")) return true
        // Link-local fe80::/10
        if (ip.startsWith("fe80") || ip.startsWith("fe90") ||
            ip.startsWith("fea0") || ip.startsWith("feb0")
        ) return true
    }
    return false
}

internal fun validateUrlSafe(url: String): Boolean {
    return try {
        val uri = URI(url)
        if (uri.scheme !in listOf("http", "https")) return false
        val host = uri.host ?: return false
        if (isInternalHost(host)) return false
        true
    } catch (_: Exception) {
        false
    }
}