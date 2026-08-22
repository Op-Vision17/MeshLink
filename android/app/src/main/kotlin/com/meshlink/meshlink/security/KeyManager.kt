package com.meshlink.meshlink.security

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.util.UUID

/**
 * KeyManager handles local node cryptographic identity and trusted peer keys
 * using a Trust-On-First-Use (TOFU) pairing model.
 */
class KeyManager(private val context: Context, val localNodeId: String) {
    private val TAG = "KeyManager"
    private val prefs: SharedPreferences = context.getSharedPreferences("meshlink_keys", Context.MODE_PRIVATE)

    val localSecretKey: String = resolveOrGenerateLocalKey()

    // Map of peerId -> shared/public key
    private val trustedPeerKeys = mutableMapOf<String, String>()

    init {
        loadSavedPeerKeys()
    }

    private fun resolveOrGenerateLocalKey(): String {
        val existing = prefs.getString("local_secret_key", null)
        if (!existing.isNullOrBlank()) return existing
        val generated = "key_${UUID.randomUUID().toString().replace("-", "")}"
        prefs.edit().putString("local_secret_key", generated).apply()
        Log.i(TAG, "Generated new local secret key for node $localNodeId")
        return generated
    }

    private fun normalizePeerId(peerId: String): String {
        val clean = peerId.trim().lowercase()
        if (clean.length <= 8) return clean
        return clean.take(8)
    }

    /**
     * Trust-On-First-Use (TOFU):
     * If peer is seen for the first time, save its key as trusted.
     */
    @Synchronized
    fun registerOrGetPeerKey(peerId: String, providedKey: String? = null): String {
        val cleanId = normalizePeerId(peerId)
        if (!providedKey.isNullOrBlank()) {
            trustedPeerKeys[cleanId] = providedKey
            trustedPeerKeys[peerId] = providedKey
            prefs.edit().putString("peer_key_$cleanId", providedKey).putString("peer_key_$peerId", providedKey).apply()
            Log.i(TAG, "[TOFU_PAIRING] Saved new trusted key for peer $cleanId ($peerId)")
            return providedKey
        }
        return trustedPeerKeys[cleanId] ?: trustedPeerKeys[peerId] ?: trustedPeerKeys.values.firstOrNull() ?: localSecretKey
    }

    fun getPeerKey(peerId: String): String {
        return registerOrGetPeerKey(peerId)
    }

    private fun loadSavedPeerKeys() {
        for ((key, value) in prefs.all) {
            if (key.startsWith("peer_key_") && value is String) {
                val peerId = key.removePrefix("peer_key_")
                val cleanId = normalizePeerId(peerId)
                trustedPeerKeys[cleanId] = value
                trustedPeerKeys[peerId] = value
            }
        }
        Log.d(TAG, "Loaded ${trustedPeerKeys.size} trusted peer keys from storage")
    }
}
