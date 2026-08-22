package com.meshlink.meshlink.mesh

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.WifiP2pManager.ActionListener
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

enum class PeerConnectionState {
    DISCOVERED, CONNECTING, CONNECTED, FAILED, DISCONNECTED
}

data class P2pPeerInfo(
    val peerId: String,
    val macAddress: String,
    val groupOwnerIp: String? = null,
    val isGroupOwner: Boolean = false,
    val connectionState: PeerConnectionState = PeerConnectionState.DISCOVERED
)

data class P2pPendingConnect(
    val peerId: String,
    val macAddress: String,
    val peerName: String? = null,
    val timestamp: Long = System.currentTimeMillis()
)

class WifiDirectManager(
    private val context: Context,
    private val localNodeId: String,
    private val onConnectionStateChanged: (peerId: String, state: PeerConnectionState, groupOwnerIp: String?) -> Unit,
    private val onError: (peerId: String?, reason: String) -> Unit
) {
    private val TAG = "WifiDirectManager"
    private val deviceTag: String get() = "[DEVICE: $localNodeId | ${android.os.Build.MODEL}]"

    private var wifiP2pManager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private val handler = Handler(Looper.getMainLooper())
    private var isRegistered = false

    // peerId → P2pPeerInfo for all known Wi-Fi peers
    private val peerInfoMap = mutableMapOf<String, P2pPeerInfo>()

    // Tracks which MAC address maps to which peerId (from BLE discovery)
    private val macToPeerId = mutableMapOf<String, String>()

    // Discovered Wi-Fi Direct devices (keyed by uppercase P2P deviceAddress)
    private val discoveredP2pDevices = ConcurrentHashMap<String, WifiP2pDevice>()

    // Pending connections waiting for P2P discovery list
    private val pendingConnectMap = ConcurrentHashMap<String, P2pPendingConnect>()

    // Local device P2P address and name (to prevent self-connection)
    private var thisDeviceAddress: String? = null
    private var thisDeviceName: String? = null

    // Tracks pending connection timeouts
    private val connectionTimeoutRunnables = mutableMapOf<String, Runnable>()
    private var p2pDiscoveryRunnable: Runnable? = null

    companion object {
        private const val CONNECTION_TIMEOUT_MS = 20_000L
        private const val DISCOVERY_RESTART_INTERVAL_MS = 15_000L
    }

    // Maps peerId -> exact P2P MAC received from BLE beacon
    private val peerToP2pMac = ConcurrentHashMap<String, String>()

    var onLocalP2pMacDiscovered: ((String) -> Unit)? = null

    private val wifiP2pReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    if (state == WifiP2pManager.WIFI_P2P_STATE_DISABLED) {
                        Log.w(TAG, "$deviceTag ⚠ Wi-Fi Direct disabled")
                        onError(null, "Wi-Fi Direct is disabled")
                    } else {
                        Log.i(TAG, "$deviceTag ✅ Wi-Fi Direct enabled")
                        startP2pDiscovery()
                    }
                }

                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    Log.d(TAG, "$deviceTag 📡 Wi-Fi Direct peers changed — requesting peer list")
                    try {
                        wifiP2pManager?.requestPeers(channel) { deviceList: WifiP2pDeviceList? ->
                            deviceList?.deviceList?.forEach { dev ->
                                val devMac = dev.deviceAddress.uppercase()
                                // Skip our own device
                                if (devMac == thisDeviceAddress || (thisDeviceName != null && dev.deviceName.equals(thisDeviceName, ignoreCase = true))) {
                                    return@forEach
                                }
                                discoveredP2pDevices[devMac] = dev
                                Log.d(TAG, "$deviceTag 📱 Discovered Wi-Fi P2P device: name=${dev.deviceName} mac=${dev.deviceAddress} status=${p2pStatusDescription(dev.status)}")
                                if (dev.status == WifiP2pDevice.INVITED) {
                                    val mappedPeerId = macToPeerId[devMac] ?: macToPeerId[dev.deviceAddress]
                                    val matchedByInfo = peerInfoMap.entries.firstOrNull { (_, info) ->
                                        info.macAddress.equals(devMac, ignoreCase = true)
                                    }?.key
                                    val targetPeerId = mappedPeerId ?: matchedByInfo ?: "peer_${dev.deviceAddress.takeLast(4)}"
                                    macToPeerId[devMac] = targetPeerId

                                    val existingState = peerInfoMap[targetPeerId]?.connectionState
                                    if (existingState != PeerConnectionState.CONNECTED) {
                                        Log.i(TAG, "$deviceTag 📩 INCOMING P2P INVITATION DETECTED from $targetPeerId (${dev.deviceName}) [status=INVITED] — setting state to CONNECTING and awaiting group formation")
                                        peerInfoMap[targetPeerId] = (peerInfoMap[targetPeerId] ?: P2pPeerInfo(targetPeerId, dev.deviceAddress)).copy(
                                            connectionState = PeerConnectionState.CONNECTING
                                        )
                                        onConnectionStateChanged(targetPeerId, PeerConnectionState.CONNECTING, null)
                                    }
                                } else if (dev.status == WifiP2pDevice.CONNECTED) {
                                    val mappedPeerId = macToPeerId[devMac] ?: macToPeerId[dev.deviceAddress]
                                    val matchedByInfo = peerInfoMap.entries.firstOrNull { (_, info) ->
                                        info.macAddress.equals(devMac, ignoreCase = true)
                                    }?.key
                                    val targetPeerId = mappedPeerId ?: matchedByInfo ?: peerInfoMap.keys.firstOrNull()

                                    Log.i(TAG, "$deviceTag 👥 P2P Device '${dev.deviceName}' ($devMac) is CONNECTED in framework (status=0) — targetPeerId=$targetPeerId — requesting connection info directly!")
                                    if (targetPeerId != null && peerInfoMap[targetPeerId]?.connectionState != PeerConnectionState.CONNECTED) {
                                        peerInfoMap[targetPeerId] = (peerInfoMap[targetPeerId] ?: P2pPeerInfo(targetPeerId, dev.deviceAddress)).copy(
                                            connectionState = PeerConnectionState.CONNECTED
                                        )
                                    }
                                    wifiP2pManager?.requestConnectionInfo(channel, connectionInfoListener)
                                }
                            }
                            handler.postDelayed({
                                processPendingConnections()
                            }, 300L)
                        }
                    } catch (e: SecurityException) {
                        Log.w(TAG, "$deviceTag Permission denied requesting peers", e)
                    }
                }

                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    val networkInfo = intent.getParcelableExtra<android.net.NetworkInfo>(
                        WifiP2pManager.EXTRA_NETWORK_INFO
                    )
                    if (networkInfo?.isConnected == true) {
                        Log.i(TAG, "$deviceTag 👥 P2P network connected — requesting connection info")
                        wifiP2pManager?.requestConnectionInfo(channel, connectionInfoListener)
                    } else {
                        Log.i(TAG, "$deviceTag 🔌 P2P network disconnected")
                        handleGroupDisconnect()
                    }
                }

                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    val device = intent.getParcelableExtra<WifiP2pDevice>(
                        WifiP2pManager.EXTRA_WIFI_P2P_DEVICE
                    )
                    thisDeviceAddress = device?.deviceAddress?.uppercase()
                    thisDeviceName = device?.deviceName
                    Log.d(TAG, "$deviceTag 🆔 This device P2P info: name=${thisDeviceName} mac=${thisDeviceAddress}")
                    thisDeviceAddress?.takeIf { !it.startsWith("02:00:00") }?.let { onLocalP2pMacDiscovered?.invoke(it) }
                }
            }
        }
    }

    private val nameToPeerIdMap = mutableMapOf<String, String>()
    private val blePeerIdSet = mutableSetOf<String>()

    fun registerBlePeer(peerId: String, peerName: String?, bleMac: String? = null, p2pMac: String? = null) {
        if (!peerName.isNullOrBlank()) {
            nameToPeerIdMap[peerName.trim().lowercase()] = peerId
        }
        if (!bleMac.isNullOrBlank()) {
            macToPeerId[bleMac.uppercase()] = peerId
        }
        if (!p2pMac.isNullOrBlank()) {
            peerToP2pMac[peerId] = p2pMac.uppercase()
            macToPeerId[p2pMac.uppercase()] = peerId
            Log.i(TAG, "Registered exact P2P MAC from BLE for peer $peerId: $p2pMac")
        }
        blePeerIdSet.add(peerId)
    }

    private fun resolvePeerIdByDeviceName(deviceName: String?): String? {
        if (deviceName.isNullOrBlank()) return null
        val clean = deviceName.trim().lowercase()

        nameToPeerIdMap[clean]?.let { return it }

        nameToPeerIdMap.entries.firstOrNull { (name, id) ->
            clean.contains(name) || name.contains(clean)
        }?.value?.let { return it }

        peerInfoMap.entries.firstOrNull { (peerId, info) ->
            clean.contains(peerId.lowercase()) || peerId.lowercase().contains(clean)
        }?.key?.let { return it }

        return blePeerIdSet.firstOrNull()
    }

    private val connectionInfoListener = WifiP2pManager.ConnectionInfoListener { info: WifiP2pInfo ->
        if (info.groupFormed) {
            val groupOwnerIp = info.groupOwnerAddress?.hostAddress
            Log.i(TAG, "Group formed. isOwner=${info.isGroupOwner} ownerIp=$groupOwnerIp")

            var peersToNotify = peerInfoMap.values
                .filter { it.connectionState == PeerConnectionState.CONNECTING }

            if (peersToNotify.isEmpty()) {
                Log.i(TAG, "Group formed (remote-initiated/startup) — resolving all registered peers to notify CONNECTED")
                val candidatePeerIds = (macToPeerId.values + blePeerIdSet + peerInfoMap.keys).distinct()
                candidatePeerIds.forEach { peerId ->
                    cancelConnectionTimeout(peerId)
                    val infoObj = P2pPeerInfo(
                        peerId = peerId,
                        macAddress = peerInfoMap[peerId]?.macAddress ?: "",
                        connectionState = PeerConnectionState.CONNECTED,
                        isGroupOwner = info.isGroupOwner,
                        groupOwnerIp = groupOwnerIp
                    )
                    peerInfoMap[peerId] = infoObj
                    Log.i(TAG, "Startup/remote group notify: peerId=$peerId ip=$groupOwnerIp isOwner=${info.isGroupOwner}")
                    onConnectionStateChanged(peerId, PeerConnectionState.CONNECTED, groupOwnerIp)
                }
            } else {
                peersToNotify.forEach { peer ->
                    cancelConnectionTimeout(peer.peerId)
                    val updated = peer.copy(
                        groupOwnerIp = groupOwnerIp,
                        isGroupOwner = info.isGroupOwner,
                        connectionState = PeerConnectionState.CONNECTED
                    )
                    peerInfoMap[peer.peerId] = updated
                    Log.i(TAG, "Direct-initiated group notify: peerId=${peer.peerId} ip=$groupOwnerIp isOwner=${info.isGroupOwner}")
                    onConnectionStateChanged(peer.peerId, PeerConnectionState.CONNECTED, groupOwnerIp)
                }
            }
        }
    }

    fun start() {
        wifiP2pManager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        if (wifiP2pManager == null) {
            Log.e(TAG, "WifiP2pManager unavailable on this device")
            onError(null, "Wi-Fi Direct not available on this device")
            return
        }

        channel = wifiP2pManager?.initialize(context, Looper.getMainLooper()) {
            Log.w(TAG, "WifiP2p channel disconnected — framework may have died")
            onError(null, "Wi-Fi Direct channel disconnected unexpectedly")
        }

        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        context.registerReceiver(wifiP2pReceiver, filter)
        isRegistered = true
        Log.i(TAG, "WifiDirectManager started")

        // Prime mThisDevice in Android WifiP2pServiceImpl framework on startup
        val activeChannel = channel
        if (activeChannel != null) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                try {
                    wifiP2pManager?.requestDeviceInfo(activeChannel) { device ->
                        if (device != null) {
                            thisDeviceAddress = device.deviceAddress?.uppercase()
                            thisDeviceName = device.deviceName
                            Log.i(TAG, "$deviceTag 🆔 Primed local P2P device info: name=$thisDeviceName mac=$thisDeviceAddress status=${p2pStatusDescription(device.status)}")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "requestDeviceInfo error on startup: ${e.message}")
                }
            }

            // Check if an active P2P group is already formed in Android OS framework on startup
            wifiP2pManager?.requestConnectionInfo(activeChannel, connectionInfoListener)
        }

        startP2pDiscovery()
        startP2pKeepAlive()
    }

    private var keepAliveHandler: Handler? = null
    private var keepAliveRunnable: Runnable? = null

    private fun startP2pKeepAlive() {
        if (keepAliveHandler == null) {
            keepAliveHandler = Handler(Looper.getMainLooper())
        }
        keepAliveRunnable?.let { keepAliveHandler?.removeCallbacks(it) }
        keepAliveRunnable = Runnable {
            if (isRegistered) {
                startP2pDiscovery()
                keepAliveHandler?.postDelayed(keepAliveRunnable!!, 30000)
            }
        }
        keepAliveHandler?.postDelayed(keepAliveRunnable!!, 30000)
    }

    /**
     * Called by MeshEngine when BLE discovers a new peer.
     * [macAddress] is the BLE device's MAC.
     * [peerId] is our stable mesh node ID for that peer.
     */
    fun connectToPeer(peerId: String, macAddress: String, peerName: String? = null) {
        if (wifiP2pManager == null || channel == null) {
            Log.e(TAG, "connectToPeer called before start()")
            onError(peerId, "Wi-Fi Direct not initialised")
            return
        }

        val existing = peerInfoMap[peerId]
        if (existing != null &&
            (existing.connectionState == PeerConnectionState.CONNECTING ||
                existing.connectionState == PeerConnectionState.CONNECTED)
        ) {
            Log.d(TAG, "Already connecting/connected to $peerId — skipping duplicate attempt")
            return
        }

        val resolvedMac = resolveTargetP2pMac(peerId, macAddress, peerName)

        if (resolvedMac == null) {
            Log.i(TAG, "P2P MAC not yet resolved for BLE MAC $macAddress (peerId=$peerId, peerName=$peerName) — queueing until Wi-Fi P2P scan completes")
            pendingConnectMap[peerId] = P2pPendingConnect(peerId, macAddress, peerName)
            peerInfoMap[peerId] = P2pPeerInfo(
                peerId = peerId,
                macAddress = macAddress,
                connectionState = PeerConnectionState.CONNECTING
            )
            onConnectionStateChanged(peerId, PeerConnectionState.CONNECTING, null)
            scheduleConnectionTimeout(peerId)
            startP2pDiscovery(forceForPending = true)
            return
        }

        executeConnect(peerId, macAddress, resolvedMac)
    }

    private fun processPendingConnections() {
        if (pendingConnectMap.isEmpty()) return
        Log.d(TAG, "Processing ${pendingConnectMap.size} pending P2P connections against ${discoveredP2pDevices.size} discovered P2P devices")
        val iterator = pendingConnectMap.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            val pending = entry.value
            val resolvedMac = resolveTargetP2pMac(pending.peerId, pending.macAddress, pending.peerName)
            if (resolvedMac != null) {
                iterator.remove()
                Log.i(TAG, "Resolved pending connection for peer ${pending.peerId}: BLE MAC ${pending.macAddress} -> P2P MAC $resolvedMac")
                executeConnect(pending.peerId, pending.macAddress, resolvedMac)
            }
        }
    }

    @Volatile
    private var isConnectInProgress = false
    private var activeRetryRunnable: Runnable? = null

    private fun executeConnect(peerId: String, originalMac: String, targetP2pMac: String, isRetry: Boolean = false) {
        if (peerInfoMap[peerId]?.connectionState == PeerConnectionState.CONNECTED) {
            Log.i(TAG, "$deviceTag Peer $peerId is ALREADY CONNECTED — skipping executeConnect")
            isConnectInProgress = false
            return
        }

        if (!isRetry && isConnectInProgress) {
            Log.d(TAG, "$deviceTag P2P Connection attempt already in flight for another operation — ignoring duplicate executeConnect")
            return
        }
        isConnectInProgress = true

        activeRetryRunnable?.let { handler.removeCallbacks(it) }
        activeRetryRunnable = null

        val cleanTargetMac = targetP2pMac.uppercase()
        macToPeerId[originalMac] = peerId

        peerInfoMap[peerId] = P2pPeerInfo(
            peerId = peerId,
            macAddress = cleanTargetMac,
            connectionState = PeerConnectionState.CONNECTING
        )
        onConnectionStateChanged(peerId, PeerConnectionState.CONNECTING, null)

        val intentVal = if (isRetry) 7 else if (localNodeId.lowercase() > peerId.lowercase()) 12 else 3

        val config: WifiP2pConfig = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            try {
                val mac = android.net.MacAddress.fromString(cleanTargetMac)
                WifiP2pConfig.Builder()
                    .setDeviceAddress(mac)
                    .setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_AUTO)
                    .build()
            } catch (_: Exception) {
                WifiP2pConfig().apply {
                    deviceAddress = cleanTargetMac
                    wps.setup = WpsInfo.PBC
                    groupOwnerIntent = intentVal
                }
            }
        } else {
            WifiP2pConfig().apply {
                deviceAddress = cleanTargetMac
                wps.setup = WpsInfo.PBC
                groupOwnerIntent = intentVal
            }
        }

        fun performActualConnect(retryCount: Int = 0) {
            if (peerInfoMap[peerId]?.connectionState == PeerConnectionState.CONNECTED) {
                Log.i(TAG, "$deviceTag Peer $peerId is ALREADY CONNECTED — aborting performActualConnect")
                isConnectInProgress = false
                return
            }

            fun doConnect() {
                if (peerInfoMap[peerId]?.connectionState == PeerConnectionState.CONNECTED) {
                    Log.i(TAG, "$deviceTag Peer $peerId became CONNECTED during delay — aborting doConnect")
                    isConnectInProgress = false
                    return
                }
                Log.i(TAG, "$deviceTag ⚡ Invoking wifiP2pManager.connect(mac=$cleanTargetMac, intent=$intentVal, retryCount=$retryCount)...")
                try {
                    wifiP2pManager?.connect(channel, config, object : ActionListener {
                        override fun onSuccess() {
                            Log.i(TAG, "$deviceTag ✅ wifiP2pManager.connect() SUCCESS callback for $peerId — awaiting group formation broadcast")
                            isConnectInProgress = false
                            scheduleConnectionTimeout(peerId)
                        }

                        override fun onFailure(reason: Int) {
                            val desc = p2pErrorDescription(reason)
                            Log.e(TAG, "$deviceTag ❌ wifiP2pManager.connect() FAILURE callback for $peerId: reasonCode=$reason ($desc) retryCount=$retryCount")

                            if (retryCount < 4 && (reason == WifiP2pManager.ERROR || reason == WifiP2pManager.BUSY)) {
                                val nextRetry = retryCount + 1
                                val backoffMs = (800L + (retryCount * 400L)).coerceAtMost(2500L)
                                Log.i(TAG, "$deviceTag 🔄 WifiP2pService busy ($reason) — waiting ${backoffMs}ms before single-flight retry $nextRetry/4")
                                val runnable = Runnable {
                                    performActualConnect(retryCount = nextRetry)
                                }
                                activeRetryRunnable = runnable
                                handler.postDelayed(runnable, backoffMs)
                                return
                            }

                            isConnectInProgress = false
                            peerInfoMap[peerId]?.let {
                                peerInfoMap[peerId] = it.copy(connectionState = PeerConnectionState.FAILED)
                            }
                            onConnectionStateChanged(peerId, PeerConnectionState.FAILED, null)
                            onError(peerId, "Connection failed: $desc")
                            startP2pDiscovery()
                        }
                    })
                } catch (e: SecurityException) {
                    Log.e(TAG, "$deviceTag NEARBY_WIFI_DEVICES permission missing for connect()", e)
                    isConnectInProgress = false
                    peerInfoMap[peerId]?.let {
                        peerInfoMap[peerId] = it.copy(connectionState = PeerConnectionState.FAILED)
                    }
                    onConnectionStateChanged(peerId, PeerConnectionState.FAILED, null)
                    onError(peerId, "Permission denied: NEARBY_WIFI_DEVICES")
                }
            }

            val hasActiveConnectedGroup = peerInfoMap.values.any { it.connectionState == PeerConnectionState.CONNECTED }
            if (hasActiveConnectedGroup) {
                wifiP2pManager?.removeGroup(channel, object : ActionListener {
                    override fun onSuccess() {
                        if (peerInfoMap[peerId]?.connectionState == PeerConnectionState.CONNECTED) {
                            Log.i(TAG, "$deviceTag Peer $peerId connected during removeGroup — aborting teardown")
                            isConnectInProgress = false
                            return
                        }
                        Log.i(TAG, "$deviceTag Removed stale P2P group — waiting 400ms before connecting to $peerId")
                        handler.postDelayed({ doConnect() }, 400L)
                    }

                    override fun onFailure(reason: Int) {
                        doConnect()
                    }
                })
            } else {
                doConnect()
            }
        }

        val currentChannel = channel
        if (thisDeviceAddress.isNullOrBlank() && currentChannel != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            try {
                wifiP2pManager?.requestDeviceInfo(currentChannel) { device ->
                    if (device != null) {
                        thisDeviceAddress = device.deviceAddress?.uppercase()
                        thisDeviceName = device.deviceName
                        Log.i(TAG, "$deviceTag 🆔 Refreshed local P2P device info before connect: name=$thisDeviceName mac=$thisDeviceAddress")
                        thisDeviceAddress?.let { onLocalP2pMacDiscovered?.invoke(it) }
                    }
                    performActualConnect()
                }
            } catch (_: Exception) {
                performActualConnect()
            }
        } else {
            performActualConnect()
        }
    }

    private fun scheduleRetryConnect(peerId: String, originalMac: String, targetP2pMac: String) {
        discoveredP2pDevices.clear()
        pendingConnectMap[peerId] = P2pPendingConnect(peerId, originalMac, null)
        startP2pDiscovery()
    }

    private fun resolveTargetP2pMac(peerId: String, requestedMac: String, peerName: String? = null): String? {
        // 0. Direct match from BLE beacon advertisement (100% accurate P2P MAC, ignoring dummy 02:00:00:00:00:00)
        peerToP2pMac[peerId]?.let { directMac ->
            if (!directMac.startsWith("02:00:00") && directMac != "02:00:00:00:00:00") {
                Log.i(TAG, "🎯 Direct P2P MAC from BLE beacon for peer $peerId: $directMac")
                return directMac
            }
        }
        val uppercaseMac = requestedMac.uppercase()

        // Exclude own device and dummy 02:00:00:00:00:00 to prevent self-connection loops
        val validP2pDevices = discoveredP2pDevices.values.filter { dev ->
            val mac = dev.deviceAddress.uppercase()
            val name = dev.deviceName
            !mac.startsWith("02:00:00") && mac != thisDeviceAddress && (thisDeviceName.isNullOrBlank() || !name.equals(thisDeviceName, ignoreCase = true))
        }

        Log.d(TAG, "🔍 resolveTargetP2pMac: peerId=$peerId, reqMac=$requestedMac, peerName='$peerName', validP2pCandidates=${validP2pDevices.size}")
        for (dev in validP2pDevices) {
            Log.d(TAG, "   ├─ Candidate P2P Device: name='${dev.deviceName}', mac='${dev.deviceAddress}', status=${p2pStatusDescription(dev.status)}")
        }

        // 1. Exact MAC match
        val exactMatch = validP2pDevices.firstOrNull { it.deviceAddress.equals(uppercaseMac, ignoreCase = true) }
        if (exactMatch != null) {
            Log.i(TAG, "Exact P2P MAC match found: ${exactMatch.deviceAddress}")
            return exactMatch.deviceAddress
        }

        // 2. Match by device name (e.g., BLE peer name vs Wi-Fi P2P device name)
        val cleanPeerName = peerName?.trim()
        if (!cleanPeerName.isNullOrBlank()) {
            val matchByName = validP2pDevices.firstOrNull { dev ->
                dev.deviceName.isNotBlank() && (
                    dev.deviceName.equals(cleanPeerName, ignoreCase = true) ||
                    dev.deviceName.contains(cleanPeerName, ignoreCase = true) ||
                    cleanPeerName.contains(dev.deviceName, ignoreCase = true)
                )
            }
            if (matchByName != null) {
                Log.i(TAG, "Matched P2P device by device name '$cleanPeerName' -> P2P MAC ${matchByName.deviceAddress}")
                return matchByName.deviceAddress
            }
        }

        // 3. Match mobile P2P device (ignore printers / TVs / infrastructure)
        val mobileP2pDevices = validP2pDevices.filter { dev ->
            !dev.deviceName.uppercase().contains("EPSON") &&
            !dev.deviceName.uppercase().contains("PRINTER") &&
            !dev.deviceName.uppercase().contains("TV") &&
            !dev.deviceName.uppercase().contains("HP")
        }

        if (mobileP2pDevices.isNotEmpty()) {
            val match = mobileP2pDevices.first()
            Log.i(TAG, "Mobile P2P device match for $peerId ('$cleanPeerName') -> P2P MAC ${match.deviceAddress}")
            return match.deviceAddress
        }

        // 4. Prefix match (matching first 5 octets)
        val reqParts = uppercaseMac.split(":")
        if (reqParts.size == 6) {
            val prefix = reqParts.take(5).joinToString(":")
            val matchByPrefix = validP2pDevices.firstOrNull { dev ->
                dev.deviceAddress.uppercase().startsWith(prefix)
            }
            if (matchByPrefix != null) {
                Log.i(TAG, "Prefix match found for $requestedMac -> P2P MAC ${matchByPrefix.deviceAddress}")
                return matchByPrefix.deviceAddress
            }
        }

        return null
    }

    fun disconnectPeer(peerId: String) {
        cancelConnectionTimeout(peerId)
        isConnectInProgress = false
        activeRetryRunnable?.let { handler.removeCallbacks(it) }
        activeRetryRunnable = null
        wifiP2pManager?.removeGroup(channel, object : ActionListener {
            override fun onSuccess() {
                Log.i(TAG, "Wi-Fi Direct group removed for $peerId")
                peerInfoMap[peerId]?.let {
                    peerInfoMap[peerId] = it.copy(connectionState = PeerConnectionState.DISCONNECTED)
                }
                onConnectionStateChanged(peerId, PeerConnectionState.DISCONNECTED, null)
            }

            override fun onFailure(reason: Int) {
                Log.w(TAG, "removeGroup failed for $peerId: ${p2pErrorDescription(reason)}")
            }
        })
    }

    fun markPeerConnectedDirectly(peerId: String, ip: String? = null) {
        val existing = peerInfoMap[peerId]
        val info = P2pPeerInfo(
            peerId = peerId,
            macAddress = existing?.macAddress ?: "",
            groupOwnerIp = ip ?: existing?.groupOwnerIp,
            isGroupOwner = existing?.isGroupOwner ?: false,
            connectionState = PeerConnectionState.CONNECTED
        )
        peerInfoMap[peerId] = info
    }

    fun getGroupOwnerIp(peerId: String): String? = peerInfoMap[peerId]?.groupOwnerIp

    fun isGroupOwner(peerId: String): Boolean = peerInfoMap[peerId]?.isGroupOwner ?: false

    fun getConnectionState(peerId: String): PeerConnectionState =
        peerInfoMap[peerId]?.connectionState ?: PeerConnectionState.DISCOVERED

    fun stop() {
        cancelAllTimeouts()
        cancelP2pDiscoveryLoop()
        if (isRegistered) {
            try {
                context.unregisterReceiver(wifiP2pReceiver)
            } catch (e: Exception) {
                Log.w(TAG, "Receiver already unregistered", e)
            }
            isRegistered = false
        }
        channel?.close()
        channel = null
        peerInfoMap.clear()
        macToPeerId.clear()
        discoveredP2pDevices.clear()
        Log.i(TAG, "WifiDirectManager stopped")
    }

    fun startP2pDiscovery(forceForPending: Boolean = false) {
        if (wifiP2pManager == null || channel == null) return
        val isConnected = peerInfoMap.values.any { it.connectionState == PeerConnectionState.CONNECTED }
        val isActivelyConnecting = peerInfoMap.values.any {
            it.connectionState == PeerConnectionState.CONNECTING && !pendingConnectMap.containsKey(it.peerId)
        }
        if (isConnected || (!forceForPending && isActivelyConnecting)) {
            Log.d(TAG, "Skipping P2P discovery because a peer is currently CONNECTED or actively CONNECTING")
            return
        }
        discoveredP2pDevices.clear()
        try {
            wifiP2pManager?.discoverPeers(channel, object : ActionListener {
                override fun onSuccess() {
                    Log.i(TAG, "wifiP2pManager.discoverPeers() succeeded")
                }

                override fun onFailure(reason: Int) {
                    Log.w(TAG, "wifiP2pManager.discoverPeers() failed: ${p2pErrorDescription(reason)}")
                    if (pendingConnectMap.isNotEmpty() && (reason == WifiP2pManager.BUSY || reason == WifiP2pManager.ERROR)) {
                        Log.i(TAG, "Pending P2P connections waiting — retrying discoverPeers() in 1000ms")
                        handler.postDelayed({ startP2pDiscovery(forceForPending = true) }, 1000L)
                    }
                }
            })
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException during discoverPeers()", e)
        }
    }

    private fun scheduleP2pDiscoveryLoop() {
        cancelP2pDiscoveryLoop()
        val runnable = object : Runnable {
            override fun run() {
                val isBusy = peerInfoMap.values.any {
                    it.connectionState == PeerConnectionState.CONNECTED ||
                    it.connectionState == PeerConnectionState.CONNECTING
                }
                if (!isBusy) {
                    startP2pDiscovery()
                } else {
                    Log.d(TAG, "Skipping periodic P2P discovery loop — connection active or in progress")
                }
                handler.postDelayed(this, DISCOVERY_RESTART_INTERVAL_MS)
            }
        }
        p2pDiscoveryRunnable = runnable
        handler.postDelayed(runnable, DISCOVERY_RESTART_INTERVAL_MS)
    }

    private fun cancelP2pDiscoveryLoop() {
        p2pDiscoveryRunnable?.let { handler.removeCallbacks(it) }
        p2pDiscoveryRunnable = null
    }

    private fun scheduleConnectionTimeout(peerId: String) {
        cancelConnectionTimeout(peerId)
        val runnable = Runnable {
            val current = peerInfoMap[peerId]
            if (current?.connectionState == PeerConnectionState.CONNECTING) {
                Log.w(TAG, "Connection to $peerId timed out")
                peerInfoMap[peerId] = current.copy(connectionState = PeerConnectionState.FAILED)
                onConnectionStateChanged(peerId, PeerConnectionState.FAILED, null)
                onError(peerId, "Connection timed out after ${CONNECTION_TIMEOUT_MS}ms")
            }
        }
        connectionTimeoutRunnables[peerId] = runnable
        handler.postDelayed(runnable, CONNECTION_TIMEOUT_MS)
    }

    private fun cancelConnectionTimeout(peerId: String) {
        connectionTimeoutRunnables.remove(peerId)?.let { handler.removeCallbacks(it) }
    }

    private fun cancelAllTimeouts() {
        connectionTimeoutRunnables.values.forEach { handler.removeCallbacks(it) }
        connectionTimeoutRunnables.clear()
    }

    private fun handleGroupDisconnect() {
        discoveredP2pDevices.clear()
        val connectedPeers = peerInfoMap.values
            .filter { it.connectionState == PeerConnectionState.CONNECTED || it.connectionState == PeerConnectionState.CONNECTING }
        connectedPeers.forEach { peer ->
            Log.w(TAG, "Group lost/disconnected for ${peer.peerId}")
            peerInfoMap[peer.peerId] = peer.copy(
                connectionState = PeerConnectionState.DISCONNECTED,
                groupOwnerIp = null
            )
            onConnectionStateChanged(peer.peerId, PeerConnectionState.DISCONNECTED, null)
        }
        handler.postDelayed({
            if (isRegistered) {
                startP2pDiscovery()
            }
        }, 1000L)
    }

    private fun p2pErrorDescription(reason: Int): String = when (reason) {
        WifiP2pManager.ERROR -> "Internal error"
        WifiP2pManager.P2P_UNSUPPORTED -> "Wi-Fi Direct unsupported"
        WifiP2pManager.BUSY -> "Framework busy — another operation in progress"
        else -> "Unknown reason ($reason)"
    }

    private fun p2pStatusDescription(status: Int): String = when (status) {
        WifiP2pDevice.CONNECTED -> "CONNECTED (0)"
        WifiP2pDevice.INVITED -> "INVITED (1)"
        WifiP2pDevice.FAILED -> "FAILED (2)"
        WifiP2pDevice.AVAILABLE -> "AVAILABLE (3)"
        WifiP2pDevice.UNAVAILABLE -> "UNAVAILABLE (4)"
        else -> "UNKNOWN ($status)"
    }
}

