package com.meshlink.meshlink.mesh

import android.os.Handler
import android.os.Looper
import com.meshlink.meshlink.model.MeshEvent
import com.meshlink.meshlink.model.Packet
import com.meshlink.meshlink.model.PacketType

class MockMeshEngine {
    private var eventListener: ((MeshEvent) -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())
    private var isDiscovering = false
    private val connectedPeers = mutableSetOf<String>()

    fun setEventListener(listener: ((MeshEvent) -> Unit)?) {
        this.eventListener = listener
    }

    fun startDiscovery(): Boolean {
        if (isDiscovering) return true
        isDiscovering = true

        handler.postDelayed({
            if (isDiscovering) {
                eventListener?.invoke(
                    MeshEvent.PeerFound(
                        peerId = "peer_alpha_101",
                        peerName = "Node Alpha (BLE)",
                        rssi = -55,
                        connectionType = "BLE"
                    )
                )
            }
        }, 1500)

        handler.postDelayed({
            if (isDiscovering) {
                eventListener?.invoke(
                    MeshEvent.PeerFound(
                        peerId = "peer_beta_202",
                        peerName = "Node Beta (Wi-Fi Direct)",
                        rssi = -68,
                        connectionType = "Wi-Fi Direct"
                    )
                )
            }
        }, 3000)

        handler.postDelayed({
            if (isDiscovering) {
                eventListener?.invoke(
                    MeshEvent.PeerFound(
                        peerId = "peer_gamma_303",
                        peerName = "Node Gamma (BLE)",
                        rssi = -74,
                        connectionType = "BLE"
                    )
                )
            }
        }, 4500)

        return true
    }

    fun stopDiscovery(): Boolean {
        isDiscovering = false
        handler.removeCallbacksAndMessages(null)
        eventListener?.invoke(
            MeshEvent.ConnectionStateChanged(
                isConnected = connectedPeers.isNotEmpty(),
                activePeersCount = connectedPeers.size
            )
        )
        return true
    }

    fun connectToPeer(peerId: String): Boolean {
        handler.postDelayed({
            connectedPeers.add(peerId)
            eventListener?.invoke(MeshEvent.PeerConnected(peerId))
            eventListener?.invoke(
                MeshEvent.ConnectionStateChanged(
                    isConnected = true,
                    activePeersCount = connectedPeers.size
                )
            )
        }, 800)
        return true
    }

    fun sendPacket(packetJson: String): Boolean {
        try {
            val originalPacket = Packet.fromJson(packetJson)
            handler.postDelayed({
                val echoPacket = originalPacket.copy(
                    messageId = "echo_${originalPacket.messageId}",
                    senderId = originalPacket.receiverId,
                    receiverId = originalPacket.senderId,
                    previousHop = "mock_relay_hop",
                    hopCount = originalPacket.hopCount + 1,
                    ttl = originalPacket.ttl - 1,
                    timestamp = System.currentTimeMillis(),
                    packetType = PacketType.ACK,
                    payload = "ACK Echo: ${originalPacket.payload}"
                )
                eventListener?.invoke(MeshEvent.PacketReceived(echoPacket.toJson()))
            }, 600)
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
}
