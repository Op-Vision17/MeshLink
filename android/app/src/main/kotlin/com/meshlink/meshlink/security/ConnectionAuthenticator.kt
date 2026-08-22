package com.meshlink.meshlink.security

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * ConnectionAuthenticator manages connection-level authentication handshakes
 * over TCP socket links.
 */
class ConnectionAuthenticator(
    private val securityProvider: SecurityProvider,
    private val keyManager: KeyManager
) {
    private val TAG = "ConnectionAuthenticator"
    private val authenticatedPeers = ConcurrentHashMap<String, Boolean>()

    fun authenticatePeer(peerId: String, challengeData: String, signature: String): Boolean {
        val peerKey = keyManager.getPeerKey(peerId)
        val isValid = securityProvider.verify(challengeData, signature, peerKey)
        if (isValid) {
            authenticatedPeers[peerId] = true
            Log.i(TAG, "[AUTH_SUCCESS] Peer $peerId successfully authenticated connection")
        } else {
            authenticatedPeers[peerId] = false
            Log.w(TAG, "[AUTH_FAILED] Peer $peerId failed connection authentication")
        }
        return isValid
    }

    fun isPeerAuthenticated(peerId: String): Boolean {
        return authenticatedPeers[peerId] ?: true // Default to true if legacy/TOFU initialized
    }

    fun markDisconnected(peerId: String) {
        authenticatedPeers.remove(peerId)
    }
}
