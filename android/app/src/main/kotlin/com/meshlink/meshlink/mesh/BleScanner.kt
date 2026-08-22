package com.meshlink.meshlink.mesh

import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.util.Log
import com.meshlink.meshlink.constants.MeshConstants
import java.nio.charset.Charset
import java.util.concurrent.ConcurrentHashMap

class BleScanner(
    private val context: Context,
    private val onPeerSeen: (peerId: String, peerName: String, rssi: Int, mac: String, p2pMac: String?) -> Unit,
    private val onScanError: (errorCode: Int, description: String) -> Unit
) {
    private val TAG = "BleScanner"

    // MAC → peerId: lets us deduplicate on re-discovery without duplicate peerFound events
    private val macToPeerId = ConcurrentHashMap<String, String>()

    private var isScanning = false

    private fun bytesToMacString(bytes: ByteArray, offset: Int = 0): String? {
        if (bytes.size < offset + 6) return null
        return try {
            (offset until offset + 6).joinToString(":") { String.format("%02X", bytes[it]) }
        } catch (_: Exception) {
            null
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            processScanResult(result)
        }

        override fun onBatchScanResults(results: List<ScanResult>) {
            results.forEach { processScanResult(it) }
        }

        override fun onScanFailed(errorCode: Int) {
            val reason = when (errorCode) {
                SCAN_FAILED_ALREADY_STARTED -> "ALREADY_STARTED"
                SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "APP_REGISTRATION_FAILED"
                SCAN_FAILED_FEATURE_UNSUPPORTED -> "FEATURE_UNSUPPORTED"
                SCAN_FAILED_INTERNAL_ERROR -> "INTERNAL_ERROR"
                else -> "UNKNOWN($errorCode)"
            }
            Log.e(TAG, "BLE scan failed: $reason")
            isScanning = false
            onScanError(errorCode, reason)
        }
    }

    private fun processScanResult(result: ScanResult) {
        val mac = try {
            result.device.address
        } catch (e: SecurityException) {
            Log.w(TAG, "Cannot read device address — BLUETOOTH_CONNECT missing?", e)
            return
        }

        val rssi = result.rssi
        val scanRecord: ScanRecord? = result.scanRecord

        // Extract peer node ID + embedded P2P MAC from manufacturer data (manufacturer ID 0x05FF = MeshLink)
        val mfrData: ByteArray? = scanRecord?.getManufacturerSpecificData(0x05FF)
        val peerId: String
        val p2pMac: String?

        if (mfrData != null && mfrData.size >= 8) {
            peerId = String(mfrData.copyOfRange(0, 8), Charset.forName("UTF-8"))
            p2pMac = if (mfrData.size >= 14) bytesToMacString(mfrData, 8) else null
        } else if (mfrData != null && mfrData.isNotEmpty()) {
            peerId = String(mfrData, Charset.forName("UTF-8"))
            p2pMac = null
        } else {
            // Fallback: derive a stable ID from the MAC
            peerId = "ble_${mac.replace(":", "")}"
            p2pMac = null
        }

        // Device name for display — prefer local name from ad record, fall back to peerId prefix
        val peerName: String = scanRecord?.deviceName?.takeIf { it.isNotBlank() }
            ?: "MeshNode-${peerId.takeLast(5)}"

        macToPeerId[mac] = peerId
        Log.d(TAG, "Scan hit: mac=$mac peerId=$peerId peerName=$peerName p2pMac=$p2pMac rssi=$rssi")
        onPeerSeen(peerId, peerName, rssi, mac, p2pMac)
    }

    fun start(): BleResult {
        if (isScanning) return BleResult.Success

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return BleResult.Error("BluetoothManager unavailable")
        val adapter = bluetoothManager.adapter
            ?: return BleResult.Error("Bluetooth adapter unavailable")

        if (!adapter.isEnabled) return BleResult.BluetoothDisabled

        val scanner = adapter.bluetoothLeScanner
            ?: return BleResult.Error("BluetoothLeScanner unavailable — Bluetooth may be turning off")

        val serviceFilter = ScanFilter.Builder()
            .setServiceUuid(MeshConstants.MESH_SERVICE_UUID)
            .build()

        val mfrFilter = ScanFilter.Builder()
            .setManufacturerData(0x05FF, byteArrayOf())
            .build()

        val filters = listOf(serviceFilter, mfrFilter)

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
            .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
            .setReportDelay(0)
            .build()

        return try {
            scanner.startScan(filters, settings, scanCallback)
            isScanning = true
            Log.i(TAG, "BLE scan started with hybrid filters (ServiceUUID + Mfr 0x05FF)")
            BleResult.Success
        } catch (e: SecurityException) {
            Log.e(TAG, "BLUETOOTH_SCAN permission missing", e)
            BleResult.PermissionDenied("BLUETOOTH_SCAN")
        }
    }

    fun stop() {
        if (!isScanning) return
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = bluetoothManager?.adapter
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException while stopping scan", e)
        }
        isScanning = false
        macToPeerId.clear()
        Log.i(TAG, "BLE scan stopped")
    }

    val isRunning: Boolean get() = isScanning
}
