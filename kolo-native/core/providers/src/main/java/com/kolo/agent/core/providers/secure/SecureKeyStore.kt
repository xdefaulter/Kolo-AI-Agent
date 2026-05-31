package com.kolo.agent.core.providers.secure

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Secure storage for API keys using Android Keystore-backed encrypted preferences.
 */
class SecureKeyStore(context: Context) {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "kolo_secure_keys",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun saveApiKey(providerId: String, key: String) {
        prefs.edit().putString("provider_apikey_$providerId", key).apply()
    }

    fun getApiKey(providerId: String): String? =
        prefs.getString("provider_apikey_$providerId", null)

    fun deleteApiKey(providerId: String) {
        prefs.edit().remove("provider_apikey_$providerId").apply()
    }
}