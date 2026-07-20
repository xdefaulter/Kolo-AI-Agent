package com.kolo.agent.core.providers.secure

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Secure storage for API keys using Android Keystore-backed encrypted preferences.
 *
 * If the encrypted store cannot be opened (e.g. keystore corruption after a backup
 * restore or ROM change), it transparently falls back to plain SharedPreferences so
 * keys remain readable/writable. Use [isSecureStorage] to detect the degraded mode.
 */
class SecureKeyStore(context: Context) {

    @Volatile
    private var isSecure: Boolean = true

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = try {
        EncryptedSharedPreferences.create(
            context,
            "kolo_secure_keys",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (e: Exception) {
        isSecure = false
        android.util.Log.e("SecureKeyStore", "Encrypted prefs unavailable, falling back to insecure storage", e)
        context.getSharedPreferences("kolo_fallback_keys", android.content.Context.MODE_PRIVATE)
    }

    fun saveApiKey(providerId: String, key: String) {
        prefs.edit().putString("provider_apikey_$providerId", key).commit()
    }

    fun getApiKey(providerId: String): String? =
        prefs.getString("provider_apikey_$providerId", null)

    fun deleteApiKey(providerId: String) {
        prefs.edit().remove("provider_apikey_$providerId").commit()
    }

    fun isSecureStorage(): Boolean = isSecure
}
