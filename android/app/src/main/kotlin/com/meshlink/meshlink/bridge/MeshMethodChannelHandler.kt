package com.meshlink.meshlink.bridge

import com.meshlink.meshlink.constants.MeshConstants
import com.meshlink.meshlink.mesh.MeshEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MeshMethodChannelHandler(private val engine: MeshEngine) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            MeshConstants.METHOD_START_DISCOVERY -> {
                val success = engine.startDiscovery()
                result.success(success)
            }
            MeshConstants.METHOD_STOP_DISCOVERY -> {
                val success = engine.stopDiscovery()
                result.success(success)
            }
            MeshConstants.METHOD_CONNECT_TO_PEER -> {
                val peerId = call.argument<String>("peerId")
                val peerName = call.argument<String>("peerName")
                val macAddress = call.argument<String>("macAddress")
                if (peerId != null) {
                    val success = engine.connectToPeer(peerId, peerName, macAddress)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "peerId argument missing", null)
                }
            }
            MeshConstants.METHOD_DISCONNECT_PEER -> {
                val peerId = call.argument<String>("peerId")
                if (peerId != null) {
                    val success = engine.disconnectPeer(peerId)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "peerId argument missing", null)
                }
            }
            MeshConstants.METHOD_SEND_PACKET -> {
                val packetJson = call.argument<String>("packetJson")
                if (packetJson != null) {
                    val success = engine.sendPacket(packetJson)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "packetJson argument missing", null)
                }
            }
            MeshConstants.METHOD_IS_BLUETOOTH_ENABLED -> {
                val isEnabled = engine.isBluetoothEnabled()
                result.success(isEnabled)
            }
            MeshConstants.METHOD_REQUEST_ENABLE_BLUETOOTH -> {
                val success = engine.requestEnableBluetooth()
                result.success(success)
            }
            MeshConstants.METHOD_IS_LOCATION_SERVICE_ENABLED -> {
                val isEnabled = engine.isLocationServiceEnabled()
                result.success(isEnabled)
            }
            MeshConstants.METHOD_REQUEST_ENABLE_LOCATION_SERVICE -> {
                val success = engine.requestEnableLocationService()
                result.success(success)
            }
            MeshConstants.METHOD_IS_WIFI_ENABLED -> {
                val isEnabled = engine.isWifiEnabled()
                result.success(isEnabled)
            }
            MeshConstants.METHOD_REQUEST_ENABLE_WIFI -> {
                val success = engine.requestEnableWifi()
                result.success(success)
            }
            MeshConstants.METHOD_UPDATE_USER_PROFILE -> {
                val displayName = call.argument<String>("displayName") ?: ""
                val avatarIndex = call.argument<Int>("avatarIndex") ?: 0
                val success = engine.updateUserProfile(displayName, avatarIndex)
                result.success(success)
            }
            MeshConstants.METHOD_OPEN_FILE -> {
                val filePath = call.argument<String>("filePath") ?: ""
                val success = engine.openFile(filePath)
                result.success(success)
            }
            MeshConstants.METHOD_SAVE_FILE_TO_DOWNLOADS -> {
                val filePath = call.argument<String>("filePath") ?: ""
                val fileName = call.argument<String>("fileName") ?: ""
                val savedPath = engine.saveFileToDownloads(filePath, fileName)
                result.success(savedPath)
            }
            MeshConstants.METHOD_CREATE_VIDEO_THUMBNAIL -> {
                val videoPath = call.argument<String>("videoPath") ?: ""
                val thumbPath = engine.createVideoThumbnail(videoPath)
                result.success(thumbPath)
            }
            "getLocalNodeId" -> {
                result.success(engine.localNodeId)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
