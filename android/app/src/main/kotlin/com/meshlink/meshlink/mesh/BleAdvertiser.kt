package com.meshlink.meshlink.mesh

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Build
import android.util.Log
import com.meshlink.meshlink.constants.MeshConstants
import java.nio.charset.Charset

class BleAdvertiser(private val context: Context, private val localNodeId: String) {
    private val TAG = "BleAdvertiser"
    private var advertiser: BluetoothLeAdvertiser? = null
    private var isAdvertising = false

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.i(TAG, "BLE advertising started. NodeId=$localNodeId")
            isAdvertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            val reason = when (errorCode) {
                ADVERTISE_FAILED_ALREADY_STARTED -> "ALREADY_STARTED"
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "DATA_TOO_LARGE"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "FEATURE_UNSUPPORTED"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "INTERNAL_ERROR"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "TOO_MANY_ADVERTISERS"
                else -> "UNKNOWN($errorCode)"
            }
            Log.e(TAG, "BLE advertising failed: $reason")
            isAdvertising = false
        }
    }

    private var localP2pMac: String? = null

    fun setLocalP2pMac(mac: String?) {
        if (!mac.isNullOrBlank() && mac != localP2pMac) {
            localP2pMac = mac.uppercase()
            Log.i(TAG, "Updated local P2P MAC for BLE beacon: $localP2pMac")
            if (isAdvertising) {
                // Restart advertising with updated manufacturer payload
                stop()
                start()
            }
        }
    }

    private fun macStringToBytes(mac: String?): ByteArray {
        if (mac.isNullOrBlank()) return ByteArray(0)
        val parts = mac.split(":")
        if (parts.size != 6) return ByteArray(0)
        return try {
            ByteArray(6) { i -> parts[i].toInt(16).toByte() }
        } catch (_: Exception) {
            ByteArray(0)
        }
    }

    fun start(): BleResult {
        if (isAdvertising) return BleResult.Success

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return BleResult.Error("BluetoothManager unavailable")
        val adapter = bluetoothManager.adapter
            ?: return BleResult.Error("Bluetooth adapter unavailable")

        if (!adapter.isEnabled) {
            return BleResult.BluetoothDisabled
        }

        if (!adapter.isMultipleAdvertisementSupported) {
            return BleResult.Error("BLE advertising not supported on this hardware")
        }

        advertiser = adapter.bluetoothLeAdvertiser
            ?: return BleResult.Error("BluetoothLeAdvertiser unavailable")

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .setTimeout(0)  // No timeout — continuous advertising
            .build()

        // Set device name safely to prevent DATA_TOO_LARGE (>31 bytes)
        try {
            val currentName = adapter.name
            if (currentName.isNullOrBlank() || currentName.length > 8) {
                adapter.name = "ML-${Build.MODEL.take(5)}"
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Cannot set bluetooth adapter name", e)
        }

        // Encode our node ID (first 8 chars) + optional 6-byte P2P MAC in manufacturer data
        val nodeIdBytes = localNodeId.take(8).toByteArray(Charset.forName("UTF-8"))
        val p2pMacBytes = macStringToBytes(localP2pMac)
        val mfrPayload = if (p2pMacBytes.size == 6) nodeIdBytes + p2pMacBytes else nodeIdBytes

        val advertiseData = AdvertiseData.Builder()
            .addServiceUuid(MeshConstants.MESH_SERVICE_UUID)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        val scanResponseData = AdvertiseData.Builder()
            .addManufacturerData(0x05FF, mfrPayload) // 0x05FF = custom MeshLink mfr ID
            .setIncludeDeviceName(true)
            .build()

        try {
            advertiser?.startAdvertising(settings, advertiseData, scanResponseData, advertiseCallback)
            return BleResult.Success
        } catch (e: SecurityException) {
            Log.e(TAG, "BLUETOOTH_ADVERTISE permission missing", e)
            return BleResult.PermissionDenied("BLUETOOTH_ADVERTISE")
        }
    }

    fun stop() {
        if (!isAdvertising) return
        try {
            advertiser?.stopAdvertising(advertiseCallback)
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException while stopping advertising", e)
        }
        isAdvertising = false
        advertiser = null
        Log.i(TAG, "BLE advertising stopped")
    }

    fun updateDisplayName(displayName: String) {
        if (displayName.isNotBlank()) {
            try {
                val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                bluetoothManager?.adapter?.name = displayName
                Log.i(TAG, "Updated Bluetooth adapter name to '$displayName'")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to update Bluetooth adapter name: ${e.message}")
            }
        }
    }

    val isRunning: Boolean get() = isAdvertising
}
