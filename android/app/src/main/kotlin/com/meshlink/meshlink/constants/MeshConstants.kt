package com.meshlink.meshlink.constants

import android.os.ParcelUuid
import java.util.UUID

object MeshConstants {
    const val METHOD_CHANNEL = "com.meshlink.app/mesh_method"
    const val EVENT_CHANNEL = "com.meshlink.app/mesh_events"

    // BLE Protocol Constants
    const val MESH_SERVICE_UUID_STRING = "0000fe55-0000-1000-8000-00805f9b34fb"
    val MESH_SERVICE_UUID: ParcelUuid = ParcelUuid.fromString(MESH_SERVICE_UUID_STRING)
    const val PEER_TIMEOUT_MS = 45000L
    const val CLEANUP_INTERVAL_MS = 5000L
    const val TCP_PORT = 8888

    // Methods
    const val METHOD_START_DISCOVERY = "startDiscovery"
    const val METHOD_STOP_DISCOVERY = "stopDiscovery"
    const val METHOD_SEND_PACKET = "sendPacket"
    const val METHOD_CONNECT_TO_PEER = "connectToPeer"
    const val METHOD_DISCONNECT_PEER = "disconnectFromPeer"
    const val METHOD_IS_BLUETOOTH_ENABLED = "isBluetoothEnabled"
    const val METHOD_REQUEST_ENABLE_BLUETOOTH = "requestEnableBluetooth"
    const val METHOD_IS_LOCATION_SERVICE_ENABLED = "isLocationServiceEnabled"
    const val METHOD_REQUEST_ENABLE_LOCATION_SERVICE = "requestEnableLocationService"
    const val METHOD_IS_WIFI_ENABLED = "isWifiEnabled"
    const val METHOD_REQUEST_ENABLE_WIFI = "requestEnableWifi"
    const val METHOD_UPDATE_USER_PROFILE = "updateUserProfile"
    const val METHOD_OPEN_FILE = "openFile"
    const val METHOD_SAVE_FILE_TO_DOWNLOADS = "saveFileToDownloads"
    const val METHOD_CREATE_VIDEO_THUMBNAIL = "createVideoThumbnail"

    // Event Types
    const val EVENT_PEER_FOUND = "peerFound"
    const val EVENT_PEER_LOST = "peerLost"
    const val EVENT_PEER_CONNECTED = "peerConnected"
    const val EVENT_PEER_DISCONNECTED = "peerDisconnected"
    const val EVENT_PACKET_RECEIVED = "packetReceived"
    const val EVENT_CONNECTION_STATE_CHANGED = "connectionStateChanged"
    const val EVENT_ERROR = "error"
}
