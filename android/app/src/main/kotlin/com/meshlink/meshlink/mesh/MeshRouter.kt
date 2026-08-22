package com.meshlink.meshlink.mesh

import android.util.Log
import com.meshlink.meshlink.model.Packet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.Collections
import java.util.LinkedHashMap

interface PacketSender {
    suspend fun sendPacket(packet: Packet, exceptHop: String? = null): Boolean
}

class MeshRouter(
    private val localNodeId: String,
    private val packetSender: PacketSender,
    private val onLocalDeliver: (Packet) -> Unit
) {
    private val TAG = "MeshRouter"
    private val maxCacheSize = 1000

    private val seenCache = Collections.synchronizedMap(
        object : LinkedHashMap<String, Boolean>(100, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Boolean>?): Boolean {
                return size > maxCacheSize
            }
        }
    )

    private fun matchesNodeId(id1: String, id2: String): Boolean {
        val a = id1.trim().lowercase()
        val b = id2.trim().lowercase()
        return a == b || a.startsWith(b) || b.startsWith(a)
    }

    fun handleIncomingPacket(packet: Packet) {
        if (packet.messageId.isBlank()) return

        // 1. Duplicate check using bounded LRU cache
        if (seenCache.containsKey(packet.messageId)) {
            Log.d(
                TAG,
                "[DROP_DUPLICATE] messageId=${packet.messageId} sender=${packet.senderId} prevHop=${packet.previousHop}"
            )
            return
        }
        seenCache[packet.messageId] = true

        val isBroadcast = packet.receiverId == "*" || packet.receiverId.equals("broadcast", ignoreCase = true)
        val isForMe = isBroadcast || matchesNodeId(packet.receiverId, localNodeId)

        // 2. Deliver locally if for this node or broadcast
        if (isForMe) {
            Log.i(
                TAG,
                "[DELIVER_LOCAL] messageId=${packet.messageId} sender=${packet.senderId} target=${packet.receiverId} hops=${packet.hopCount} ttl=${packet.ttl}"
            )
            onLocalDeliver(packet)
        }

        // 3. Forward packet if broadcast or targeted to another node (and NOT targeted exclusively to me)
        if (isBroadcast || !matchesNodeId(packet.receiverId, localNodeId)) {
            if (packet.ttl - 1 <= 0) {
                Log.w(
                    TAG,
                    "[DROP_TTL_EXPIRED] messageId=${packet.messageId} sender=${packet.senderId} target=${packet.receiverId} hops=${packet.hopCount} ttl=${packet.ttl}"
                )
                return
            }

            val forwardedPacket = packet.copy(
                previousHop = localNodeId,
                hopCount = packet.hopCount + 1,
                ttl = packet.ttl - 1
            )

            Log.i(
                TAG,
                "[FORWARD] messageId=${forwardedPacket.messageId} sender=${forwardedPacket.senderId} target=${forwardedPacket.receiverId} newHop=${forwardedPacket.hopCount} newTtl=${forwardedPacket.ttl} via=$localNodeId exceptPrevHop=${packet.previousHop}"
            )

            CoroutineScope(Dispatchers.IO).launch {
                packetSender.sendPacket(forwardedPacket, exceptHop = packet.previousHop)
            }
        }
    }

    suspend fun handleOutgoingPacket(packet: Packet): Boolean {
        if (packet.messageId.isNotBlank()) {
            seenCache[packet.messageId] = true
        }

        val updatedPacket = if (packet.senderId.isBlank() || packet.senderId == "local") {
            packet.copy(senderId = localNodeId, previousHop = localNodeId)
        } else {
            packet.copy(previousHop = localNodeId)
        }

        Log.i(
            TAG,
            "[SEND_OUTGOING] messageId=${updatedPacket.messageId} sender=${updatedPacket.senderId} target=${updatedPacket.receiverId} hops=${updatedPacket.hopCount} ttl=${updatedPacket.ttl}"
        )

        return packetSender.sendPacket(updatedPacket, exceptHop = null)
    }

    fun clearCache() {
        seenCache.clear()
    }
}
