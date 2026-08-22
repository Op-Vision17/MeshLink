package com.meshlink.meshlink.model

import com.meshlink.meshlink.constants.MeshConstants

sealed class MeshEvent {
    abstract val eventType: String
    abstract fun toMap(): Map<String, Any?>

    data class PeerFound(
        val peerId: String,
        val peerName: String,
        val rssi: Int = -60,
        val connectionType: String = "BLE"
    ) : MeshEvent() {
        override val eventType: String = MeshConstants.EVENT_PEER_FOUND
        override fun toMap(): Map<String, Any?> = mapOf(
            "eventType" to eventType,
            "peerId" to peerId,
            "peerName" to peerName,
            "rssi" to rssi,
            "connectionType" to connectionType
        )
    }

    data class PeerLost(val peerId: String) : MeshEvent() {
        override val eventType: String = MeshConstants.EVENT_PEER_LOST
        override fun toMap(): Map<String, Any?> = mapOf(
            "eventType" to eventType,
            "peerId" to peerId
        )
    }

    data class PeerConnected(
        val peerId: String,
        val groupOwnerIp: String? = null,
        val isGroupOwner: Boolean = false
    ) : MeshEvent() {
        override val eventType: String = MeshConstants.EVENT_PEER_CONNECTED
        override fun toMap(): Map<String, Any?> = mapOf(
            "eventType" to eventType,
            "peerId" to peerId,
            "groupOwnerIp" to groupOwnerIp,
            "isGroupOwner" to isGroupOwner
        )
    }

    data class PeerDisconnected(val peerId: String) : MeshEvent() {
        override val eventType: String = MeshConstants.EVENT_PEER_DISCONNECTED
        override fun toMap(): Map<String, Any?> = mapOf(
            "eventType" to eventType,
            "peerId" to peerId
        )
    }

    data class PacketReceived(val packetJson: String) : MeshEvent() {
        override val eventType: String = MeshConstants.EVENT_PACKET_RECEIVED
        override fun toMap(): Map<String, Any?> = mapOf(
            "eventType" to eventType,
            "packetJson" to packetJson
        )
    }

    /**
     * Emitted for global connection state changes (existing fields) AND
     * per-peer Wi-Fi Direct state changes (peerId + connectionState).
     * Additive — existing Flutter consumers reading only isConnected/activePeersCount
     * are unaffected by the new optional fields.
     */
    data class ConnectionStateChanged(
        val isConnected: Boolean,
        val activePeersCount: Int,
        val peerId: String? = null,
        val connectionState: String? = null  // "connecting" | "connected" | "failed" | "disconnected"
    ) : MeshEvent() {
        override val eventType: String = MeshConstants.EVENT_CONNECTION_STATE_CHANGED
        override fun toMap(): Map<String, Any?> = mapOf(
            "eventType" to eventType,
            "isConnected" to isConnected,
            "activePeersCount" to activePeersCount,
            "peerId" to peerId,
            "connectionState" to connectionState
        )
    }

    data class MeshError(val errorCode: String, val message: String) : MeshEvent() {
        override val eventType: String = MeshConstants.EVENT_ERROR
        override fun toMap(): Map<String, Any?> = mapOf(
            "eventType" to eventType,
            "errorCode" to errorCode,
            "message" to message
        )
    }
}
