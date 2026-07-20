package com.kolo.agent.core.tools.builtin

import org.junit.Assert.*
import org.junit.Test

class HttpSafetyTest {

    // ---- isInternalHost: internal hosts should return true ----

    @Test
    fun localhostIsInternal() {
        assertTrue(isInternalHost("localhost"))
    }

    @Test
    fun loopbackV4IsInternal() {
        assertTrue(isInternalHost("127.0.0.1"))
        assertTrue(isInternalHost("127.1.2.3"))
    }

    @Test
    fun classAPrivateIsInternal() {
        assertTrue(isInternalHost("10.0.0.1"))
        assertTrue(isInternalHost("10.255.255.255"))
    }

    @Test
    fun classCPrivateIsInternal() {
        assertTrue(isInternalHost("192.168.0.1"))
        assertTrue(isInternalHost("192.168.1.100"))
    }

    @Test
    fun classBPrivateRangeIsInternal() {
        assertTrue(isInternalHost("172.16.0.1"))
        assertTrue(isInternalHost("172.31.255.255"))
    }

    @Test
    fun classBJustBelowRangeIsNotInternal() {
        assertFalse(isInternalHost("172.15.0.1"))
    }

    @Test
    fun classBJustAboveRangeIsNotInternal() {
        assertFalse(isInternalHost("172.32.0.1"))
    }

    @Test
    fun linkLocalV4IsInternal() {
        assertTrue(isInternalHost("169.254.1.1"))
    }

    @Test
    fun cgnatRangeIsInternal() {
        assertTrue(isInternalHost("100.64.0.1"))
        assertTrue(isInternalHost("100.127.255.255"))
    }

    @Test
    fun cgnatJustBelowRangeIsNotInternal() {
        assertFalse(isInternalHost("100.63.0.1"))
    }

    @Test
    fun cgnatJustAboveRangeIsNotInternal() {
        assertFalse(isInternalHost("100.128.0.1"))
    }

    @Test
    fun unspecifiedAndLoopbackV6AreInternal() {
        assertTrue(isInternalHost("0.0.0.0"))
        assertTrue(isInternalHost("::"))
        assertTrue(isInternalHost("::1"))
    }

    @Test
    fun bracketedLoopbackV6IsInternal() {
        assertTrue(isInternalHost("[::1]"))
    }

    @Test
    fun ipv6UlaIsInternal() {
        assertTrue(isInternalHost("[fc00::1]"))
        assertTrue(isInternalHost("[fd12:3456::1]"))
    }

    @Test
    fun ipv6LinkLocalIsInternal() {
        assertTrue(isInternalHost("[fe80::1]"))
    }

    @Test
    fun publicHostsAreNotInternal() {
        assertFalse(isInternalHost("8.8.8.8"))
        assertFalse(isInternalHost("1.1.1.1"))
        assertFalse(isInternalHost("example.com"))
        assertFalse(isInternalHost("github.com"))
    }

    // ---- validateUrlSafe ----

    @Test
    fun httpUrlToPublicHostIsSafe() {
        assertTrue(validateUrlSafe("http://example.com/path"))
    }

    @Test
    fun httpsUrlToPublicHostIsSafe() {
        assertTrue(validateUrlSafe("https://example.com"))
    }

    @Test
    fun httpUrlToLocalhostIsUnsafe() {
        assertFalse(validateUrlSafe("http://localhost:8080"))
    }

    @Test
    fun httpUrlToLoopbackIsUnsafe() {
        assertFalse(validateUrlSafe("http://127.0.0.1"))
    }

    @Test
    fun httpUrlToPrivateRangeIsUnsafe() {
        assertFalse(validateUrlSafe("http://192.168.1.1"))
    }

    @Test
    fun ftpSchemeIsUnsafe() {
        assertFalse(validateUrlSafe("ftp://example.com"))
    }

    @Test
    fun javascriptSchemeIsUnsafe() {
        assertFalse(validateUrlSafe("javascript:alert(1)"))
    }

    @Test
    fun nonUrlIsUnsafe() {
        assertFalse(validateUrlSafe("not-a-url"))
    }

    @Test
    fun httpUrlToPublicIpIsSafe() {
        assertTrue(validateUrlSafe("http://8.8.8.8"))
    }
}
