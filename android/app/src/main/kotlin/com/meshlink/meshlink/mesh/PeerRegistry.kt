package com.meshlink.meshlink.mesh

import android.util.Log
import com.meshlink.meshlink.constants.MeshConstants
import java.util.concurrent.ConcurrentHashMap

data class PeerEntry(
    val peerId: String,
    val peerName: String,
    val rssi: Int,
    val connectionType: String = "BLE",
    val lastSeenMs: Long = System.currentTimeMillis()
)

class PeerRegistry {
    private val TAG = "PeerRegistry"
    private val peers = ConcurrentHashMap<String, PeerEntry>()

    // Returns true if this is a NEW peer (not previously known)
    fun upsert(entry: PeerEntry): Boolean {
        val existing = peers[entry.peerId]
        peers[entry.peerId] = entry
        return existing == null
    }

    // Returns list of peer IDs that have timed out and removes them
    fun evictExpired(): List<PeerEntry> {
        val now = System.currentTimeMillis()
        val expired = peers.values.filter { now - it.lastSeenMs > MeshConstants.PEER_TIMEOUT_MS }
        expired.forEach { peers.remove(it.peerId) }
        if (expired.isNotEmpty()) {
            Log.d(TAG, "Evicted ${expired.size} expired peer(s): ${expired.map { it.peerId }}")
        }
        return expired
    }

    fun get(peerId: String): PeerEntry? = peers[peerId]

    fun all(): List<PeerEntry> = peers.values.toList()

    fun clearDisconnectedPeers(isConnected: (String) -> Boolean) {
        val toRemove = peers.keys.filter { !isConnected(it) }
        toRemove.forEach { peers.remove(it) }
        if (toRemove.isNotEmpty()) {
            Log.d(TAG, "Cleared ${toRemove.size} disconnected peer(s) from registry on fresh scan start")
        }
    }

    fun clear() = peers.clear()
}
