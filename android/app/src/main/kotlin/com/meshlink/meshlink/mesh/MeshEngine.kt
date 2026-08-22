package com.meshlink.meshlink.mesh

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.meshlink.meshlink.constants.MeshConstants
import com.meshlink.meshlink.model.MeshEvent
import com.meshlink.meshlink.model.Packet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * MeshEngine is the single coordinator for all mesh networking on the native side.
 * It owns BleAdvertiser, BleScanner, PeerRegistry, and WifiDirectManager, and
 * routes internal callbacks into MeshEvent emissions on the EventChannel.
 *
 * The Flutter side is completely unaware of any of these internals.
 */
class MeshEngine(private val context: Context) {
    private val TAG = "MeshEngine"

    val localNodeId: String = resolveOrGenerateNodeId()
    private val deviceTag: String get() = "[NODE: $localNodeId | ${android.os.Build.MODEL}]"

    private val peerRegistry = PeerRegistry()
    private val bleAdvertiser = BleAdvertiser(context, localNodeId)
    private val bleScanner = BleScanner(
        context = context,
        onPeerSeen = ::onBlePeerSeen,
        onScanError = ::onBleScanError
    )
    private val wifiDirectManager = WifiDirectManager(
        context = context,
        localNodeId = localNodeId,
        onConnectionStateChanged = ::onWifiConnectionStateChanged,
        onError = ::onWifiError
    ).apply {
        onLocalP2pMacDiscovered = { p2pMac ->
            Log.i(TAG, "Syncing local P2P MAC $p2pMac to BLE advertiser")
            bleAdvertiser.setLocalP2pMac(p2pMac)
        }
        onP2pDeviceDiscovered = { peerId, peerName, p2pMac ->
            onP2pPeerSeen(peerId, peerName, p2pMac)
        }
    }

    private val outboxQueue = java.util.concurrent.ConcurrentLinkedQueue<Packet>()

    private fun flushOutboxQueue() {
        if (outboxQueue.isEmpty()) return
        Log.i(TAG, "📦 Flushing ${outboxQueue.size} pending packet(s) from outbox queue over new socket connection...")
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            kotlinx.coroutines.delay(200L)
            while (outboxQueue.isNotEmpty()) {
                val queuedPacket = outboxQueue.peek() ?: break
                val success = meshRouter.handleOutgoingPacket(queuedPacket)
                if (success) {
                    outboxQueue.poll()
                    Log.i(TAG, "✅ Flushed queued packet ${queuedPacket.messageId} to ${queuedPacket.receiverId}")
                } else {
                    Log.w(TAG, "Failed to flush queued packet ${queuedPacket.messageId} — pausing outbox flush")
                    break
                }
            }
        }
    }

    private val socketManager = SocketManager(
        onPacketReceived = ::onSocketPacketReceived,
        onError = ::onSocketError
    ).apply {
        onSocketConnected = {
            Log.i(TAG, "Socket stream connected — sending immediate handshake packet")
            sendHandshakePacket()
            flushOutboxQueue()
        }
        onSocketDisconnected = {
            onRemotePeerSocketDisconnected()
        }
    }
    private val socketServer = SocketServer(socketManager)
    private val socketClient = SocketClient(socketManager)

    val keyManager = com.meshlink.meshlink.security.KeyManager(context, localNodeId)
    val securityProvider: com.meshlink.meshlink.security.SecurityProvider = com.meshlink.meshlink.security.AesGcmSecurityProvider()
    val connectionAuthenticator = com.meshlink.meshlink.security.ConnectionAuthenticator(securityProvider, keyManager)

    private val meshRouter = MeshRouter(
        localNodeId = localNodeId,
        packetSender = object : PacketSender {
            override suspend fun sendPacket(packet: Packet, exceptHop: String?): Boolean {
                return socketManager.sendPacket(packet, exceptHop)
            }
        },
        onLocalDeliver = { packet ->
            val cleanSender = packet.senderId.take(8).lowercase()
            val cleanReceiver = packet.receiverId.take(8).lowercase()
            val peerKey = keyManager.getPeerKey(packet.senderId) ?: keyManager.getPeerKey(cleanSender)

            var decryptedPayload = try {
                securityProvider.decrypt(packet.payload, peerKey)
            } catch (_: Exception) {
                packet.payload
            }
            if (decryptedPayload == packet.payload) {
                decryptedPayload = try {
                    securityProvider.decrypt(packet.payload, keyManager.localSecretKey)
                } catch (_: Exception) {
                    packet.payload
                }
            }

            val decryptedPacket = packet.copy(
                senderId = cleanSender,
                receiverId = cleanReceiver,
                payload = decryptedPayload
            )
            Log.i(TAG, "[DELIVER_TO_FLUTTER] sender=$cleanSender receiver=$cleanReceiver payload=$decryptedPayload")
            emit(MeshEvent.PacketReceived(decryptedPacket.toJson()))
        }
    )

    private var eventListener: ((MeshEvent) -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())
    private var cleanupRunnable: Runnable? = null
    private var isRunning = false

    var localDisplayName: String = ""
        private set
    var localAvatarIndex: Int = 0
        private set

    fun updateUserProfile(displayName: String, avatarIndex: Int): Boolean {
        Log.i(TAG, "Updating local user profile: displayName='$displayName', avatarIndex=$avatarIndex")
        localDisplayName = displayName
        localAvatarIndex = avatarIndex
        try {
            prefs.edit().putString("local_display_name", displayName).putInt("local_avatar_index", avatarIndex).apply()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to persist local profile: ${e.message}")
        }
        bleAdvertiser.updateDisplayName(displayName)
        return true
    }

    // Tracks MAC addresses from BLE scans for Wi-Fi Direct connection keying
    private val peerIdToMac = mutableMapOf<String, String>()
    private val prefs by lazy { context.getSharedPreferences("meshlink_peers", android.content.Context.MODE_PRIVATE) }

    private fun saveMacForPeer(peerId: String, mac: String) {
        peerIdToMac[peerId] = mac
        try {
            prefs.edit().putString("mac_$peerId", mac).apply()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to save MAC for $peerId: ${e.message}")
        }
    }

    private fun getMacForPeer(peerId: String): String? {
        val cached = peerIdToMac[peerId]
        if (cached != null) return cached
        val persisted = try { prefs.getString("mac_$peerId", null) } catch (_: Exception) { null }
        if (persisted != null) {
            peerIdToMac[peerId] = persisted
        }
        return persisted
    }

    fun setEventListener(listener: ((MeshEvent) -> Unit)?) {
        eventListener = listener
    }

    private fun autoEnableHardwareIfNeeded() {
        try {
            val btAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
            if (btAdapter != null && !btAdapter.isEnabled) {
                Log.i(TAG, "Bluetooth is disabled — attempting automatic programmatic enable")
                @Suppress("DEPRECATION")
                val success = btAdapter.enable()
                Log.i(TAG, "Programmatic Bluetooth enable result: $success")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Bluetooth auto-enable failed: ${e.message}")
        }

        try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager
            if (wifiManager != null && !wifiManager.isWifiEnabled) {
                Log.i(TAG, "Wi-Fi is disabled — attempting automatic programmatic enable")
                @Suppress("DEPRECATION")
                wifiManager.isWifiEnabled = true
                Log.i(TAG, "Programmatic Wi-Fi enable triggered")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Wi-Fi auto-enable failed: ${e.message}")
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    fun startDiscovery(): Boolean {
        if (!checkPermissionsOrEmitError()) {
            return false
        }

        autoEnableHardwareIfNeeded()

        Log.i(TAG, "$deviceTag 🚀 Starting/Refreshing mesh discovery...")
        try {
            com.meshlink.meshlink.service.MeshForegroundService.startService(context)
        } catch (e: Exception) {
            Log.w(TAG, "Could not start MeshForegroundService: ${e.message}")
        }

        // Restart BLE components to trigger fresh scan callbacks
        bleScanner.stop()
        bleAdvertiser.stop()

        // Clear stale disconnected peers from native registry
        peerRegistry.clearDisconnectedPeers { peerId ->
            wifiDirectManager.getConnectionState(peerId) == PeerConnectionState.CONNECTED
        }

        wifiDirectManager.start()

        // Ensure SocketServer port 8888 is active and ready for incoming P2P connections
        Log.i(TAG, "Ensuring SocketServer is active on port ${MeshConstants.TCP_PORT}")
        socketServer.start(MeshConstants.TCP_PORT)

        val advertiseResult = bleAdvertiser.start()
        if (!advertiseResult.isSuccess) {
            Log.e(TAG, "BLE advertise failed: ${advertiseResult.toErrorCode()}")
            emit(MeshEvent.MeshError(advertiseResult.toErrorCode(), "BLE advertising could not start"))
            if (advertiseResult is BleResult.BluetoothDisabled) {
                emit(MeshEvent.MeshError("BLUETOOTH_DISABLED", "Enable Bluetooth to use MeshLink"))
                return false
            }
        }

        val scanResult = bleScanner.start()
        if (!scanResult.isSuccess) {
            Log.e(TAG, "BLE scan failed: ${scanResult.toErrorCode()}")
            emit(MeshEvent.MeshError(scanResult.toErrorCode(), "BLE scanning could not start"))
            if (scanResult is BleResult.BluetoothDisabled) {
                emit(MeshEvent.MeshError("BLUETOOTH_DISABLED", "Enable Bluetooth to use MeshLink"))
                bleAdvertiser.stop()
                return false
            }
        }

        wifiDirectManager.start()
        socketServer.start(MeshConstants.TCP_PORT)

        isRunning = bleAdvertiser.isRunning || bleScanner.isRunning

        // Re-emit currently connected active peers
        peerRegistry.all().filter { peer ->
            wifiDirectManager.getConnectionState(peer.peerId) == PeerConnectionState.CONNECTED
        }.forEach { peer ->
            emit(MeshEvent.PeerFound(peerId = peer.peerId, peerName = peer.peerName, rssi = peer.rssi))
        }

        if (isRunning) {
            scheduleCleanup()
        }
        return isRunning
    }

    fun stopDiscovery(): Boolean {
        Log.i(TAG, "Stopping mesh BLE scanning (keeping P2P listener active for incoming connections)")
        try {
            com.meshlink.meshlink.service.MeshForegroundService.stopService(context)
        } catch (e: Exception) {
            Log.w(TAG, "Could not stop MeshForegroundService: ${e.message}")
        }
        bleScanner.stop()
        bleAdvertiser.stop()
        isRunning = false
        emit(MeshEvent.ConnectionStateChanged(isConnected = connectedPeersCount() > 0, activePeersCount = connectedPeersCount()))
        return true
    }

    private fun checkPermissionsOrEmitError(): Boolean {
        val required = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            listOf(
                android.Manifest.permission.BLUETOOTH_SCAN,
                android.Manifest.permission.BLUETOOTH_ADVERTISE,
                android.Manifest.permission.BLUETOOTH_CONNECT,
                android.Manifest.permission.NEARBY_WIFI_DEVICES
            )
        } else {
            listOf(
                android.Manifest.permission.ACCESS_FINE_LOCATION,
                android.Manifest.permission.ACCESS_COARSE_LOCATION
            )
        }
        for (perm in required) {
            if (androidx.core.content.ContextCompat.checkSelfPermission(context, perm) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                Log.e(TAG, "Required permission missing or revoked: $perm")
                emit(MeshEvent.MeshError("PERMISSION_REVOKED", "Required permission revoked: $perm"))
                return false
            }
        }
        return true
    }

    fun connectToPeer(peerId: String, peerName: String? = null, macAddress: String? = null): Boolean {
        wifiDirectManager.start()
        wifiDirectManager.startP2pDiscovery(forceForPending = true)

        // Ensure socket server is active for fresh TCP connections upon reconnection
        socketServer.start(MeshConstants.TCP_PORT)

        if (!peerName.isNullOrBlank()) {
            peerRegistry.upsert(PeerEntry(peerId, peerName, -60))
            wifiDirectManager.registerBlePeer(peerId, peerName, macAddress)
        }

        val entry = peerRegistry.get(peerId)
        val targetPeerName = peerName ?: entry?.peerName
        val mac = macAddress.takeIf { !it.isNullOrBlank() } ?: getMacForPeer(peerId)

        Log.i(TAG, "connectToPeer: target peerId=$peerId, resolved mac=$mac, peerName=$targetPeerName")
        wifiDirectManager.connectToPeer(peerId, mac ?: "", peerName = targetPeerName)
        return true
    }

    fun disconnectPeer(peerId: String): Boolean {
        val cleanId = peerId.take(8).lowercase()
        handshookPeers.remove(cleanId)
        handshookPeers.remove(peerId)
        Log.i(TAG, "Disconnecting peer requested: $peerId")
        wifiDirectManager.disconnectPeer(peerId)
        socketManager.stopAll()
        emit(MeshEvent.ConnectionStateChanged(
            isConnected = connectedPeersCount() > 0,
            activePeersCount = connectedPeersCount(),
            peerId = peerId,
            connectionState = "disconnected"
        ))
        return true
    }

    fun sendPacket(packetJson: String): Boolean {
        return try {
            val packet = Packet.fromJson(packetJson)
            val sender = if (packet.senderId.isBlank() || packet.senderId == "local") localNodeId else packet.senderId
            val peerKey = keyManager.getPeerKey(packet.receiverId)

            val encryptedPayload = securityProvider.encrypt(packet.payload, peerKey)
            val signData = "$sender:${packet.messageId}:$encryptedPayload"
            val signature = securityProvider.sign(signData, keyManager.localSecretKey)

            val securedPacket = packet.copy(
                senderId = sender,
                payload = encryptedPayload,
                signature = signature
            )

            Log.d(TAG, "sendPacket [SECURED] via MeshRouter: id=${securedPacket.messageId} to=${securedPacket.receiverId} sig=${signature.take(8)}…")
            val sent = kotlinx.coroutines.runBlocking {
                meshRouter.handleOutgoingPacket(securedPacket)
            }
            if (!sent) {
                Log.i(TAG, "📦 Socket not active yet — queuing packet ${securedPacket.messageId} in Store-and-Forward Outbox")
                outboxQueue.offer(securedPacket)
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "sendPacket failed: ${e.message}", e)
            emit(MeshEvent.MeshError("BAD_PACKET", "Could not parse or send packet: ${e.message}"))
            false
        }
    }

    // ── Internal BLE callbacks ─────────────────────────────────────────────────

    private fun onBlePeerSeen(peerId: String, peerName: String, rssi: Int, mac: String, p2pMac: String? = null) {
        // Ignore self-advertisements
        if (peerId.equals(localNodeId, ignoreCase = true) || peerId.startsWith(localNodeId) || localNodeId.startsWith(peerId)) {
            Log.v(TAG, "Ignoring self-discovered BLE advertisement (peerId=$peerId, localNodeId=$localNodeId)")
            return
        }

        val entry = PeerEntry(
            peerId = peerId,
            peerName = peerName,
            rssi = rssi,
            lastSeenMs = System.currentTimeMillis()
        )
        saveMacForPeer(peerId, mac)
        wifiDirectManager.registerBlePeer(peerId, peerName, bleMac = mac, p2pMac = p2pMac)

        val isNew = peerRegistry.upsert(entry)
        Log.d(TAG, "Peer seen (isNew=$isNew): $peerId ($peerName) mac=$mac p2pMac=$p2pMac rssi=$rssi")
        emit(MeshEvent.PeerFound(peerId = peerId, peerName = peerName, rssi = rssi))
    }

    private fun onP2pPeerSeen(peerId: String, peerName: String, p2pMac: String) {
        val entry = PeerEntry(
            peerId = peerId,
            peerName = peerName,
            rssi = -55,
            connectionType = "Wi-Fi Direct"
        )
        wifiDirectManager.registerBlePeer(peerId, peerName, p2pMac = p2pMac)
        val isNew = peerRegistry.upsert(entry)
        Log.d(TAG, "P2P Peer seen via Wi-Fi Direct (isNew=$isNew): $peerId ($peerName) p2pMac=$p2pMac")
        emit(MeshEvent.PeerFound(peerId = peerId, peerName = peerName, rssi = -55))
    }

    private fun onBleScanError(errorCode: Int, description: String) {
        Log.e(TAG, "BLE scan error $errorCode: $description")
        emit(MeshEvent.MeshError("BLE_SCAN_ERROR:$errorCode", description))
    }

    // ── Internal Wi-Fi Direct callbacks ───────────────────────────────────────

    private fun onWifiConnectionStateChanged(
        peerId: String,
        state: PeerConnectionState,
        groupOwnerIp: String?
    ) {
        Log.i(TAG, "Wi-Fi Direct state for $peerId: $state  ownerIp=$groupOwnerIp")
        when (state) {
            PeerConnectionState.CONNECTING -> {
                emit(MeshEvent.ConnectionStateChanged(
                    isConnected = false,
                    activePeersCount = connectedPeersCount(),
                    peerId = peerId,
                    connectionState = "connecting"
                ))
            }
            PeerConnectionState.CONNECTED -> {
                val isOwner = wifiDirectManager.isGroupOwner(peerId)
                Log.i(TAG, "Starting SocketServer on port ${MeshConstants.TCP_PORT} (isOwner=$isOwner)")
                socketServer.start(MeshConstants.TCP_PORT)

                if (!isOwner && groupOwnerIp != null) {
                    Log.i(TAG, "Device is Client — connecting SocketClient to $groupOwnerIp:${MeshConstants.TCP_PORT}")
                    handler.postDelayed({
                        socketClient.connect(groupOwnerIp, MeshConstants.TCP_PORT)
                    }, 500)
                }

                // Send handshake to exchange security keys over socket connection
                handler.postDelayed({
                    sendHandshakePacket(peerId)
                }, 1200)

                emit(MeshEvent.PeerConnected(
                    peerId = peerId,
                    groupOwnerIp = groupOwnerIp,
                    isGroupOwner = isOwner
                ))
                emit(MeshEvent.ConnectionStateChanged(
                    isConnected = true,
                    activePeersCount = connectedPeersCount(),
                    peerId = peerId,
                    connectionState = "connected"
                ))
            }
            PeerConnectionState.FAILED -> {
                emit(MeshEvent.ConnectionStateChanged(
                    isConnected = false,
                    activePeersCount = connectedPeersCount(),
                    peerId = peerId,
                    connectionState = "failed"
                ))
            }
            PeerConnectionState.DISCONNECTED -> {
                socketManager.stopAll()
                emit(MeshEvent.PeerDisconnected(peerId))
                emit(MeshEvent.ConnectionStateChanged(
                    isConnected = false,
                    activePeersCount = connectedPeersCount(),
                    peerId = peerId,
                    connectionState = "disconnected"
                ))
            }
            PeerConnectionState.DISCOVERED -> { /* no event */ }
        }
    }

    private fun onWifiError(peerId: String?, reason: String) {
        Log.e(TAG, "Wi-Fi Direct error (peer=$peerId): $reason")
        emit(MeshEvent.MeshError("WIFI_DIRECT_ERROR", reason))
    }

    private fun onRemotePeerSocketDisconnected() {
        Log.i(TAG, "All socket streams closed / dropped by remote peer — syncing disconnected state to Flutter")
        val connectedPeers = peerRegistry.all().filter {
            wifiDirectManager.getConnectionState(it.peerId) == PeerConnectionState.CONNECTED
        }
        for (peer in connectedPeers) {
            handshookPeers.remove(peer.peerId.take(8).lowercase())
            handshookPeers.remove(peer.peerId)
            onWifiConnectionStateChanged(peer.peerId, PeerConnectionState.DISCONNECTED, null)
            emit(MeshEvent.PeerDisconnected(peer.peerId))
            emit(MeshEvent.ConnectionStateChanged(
                isConnected = false,
                activePeersCount = 0,
                peerId = peer.peerId,
                connectionState = "disconnected"
            ))
        }
    }

    // ── Internal Socket callbacks ─────────────────────────────────────────────

    private fun sendHandshakePacket(targetPeerId: String? = null) {
        val handshakeJson = org.json.JSONObject().apply {
            put("key", keyManager.localSecretKey)
            put("name", if (localDisplayName.isNotBlank()) localDisplayName else "User ${localNodeId.take(4)}")
            put("avatar", localAvatarIndex)
        }.toString()

        val packet = Packet(
            messageId = "hs_${System.currentTimeMillis()}",
            senderId = localNodeId,
            receiverId = targetPeerId ?: "*",
            packetType = com.meshlink.meshlink.model.PacketType.HANDSHAKE,
            payload = handshakeJson,
            signature = securityProvider.sign("handshake:$localNodeId", keyManager.localSecretKey)
        )
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            socketManager.sendPacket(packet)
        }
    }

    private val handshookPeers = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    private fun markPeerConnectedFromSocket(rawSenderId: String) {
        if (rawSenderId.isBlank() || rawSenderId == "local") return
        val cleanSender = rawSenderId.take(8).lowercase()
        val entry = peerRegistry.get(cleanSender) ?: PeerEntry(cleanSender, "Peer $cleanSender", 0, "Wi-Fi Direct")
        peerRegistry.upsert(entry)
        val currentState = wifiDirectManager.getConnectionState(cleanSender)
        if (currentState != PeerConnectionState.CONNECTED) {
            Log.i(TAG, "⚡ Automatically marking peer $cleanSender as CONNECTED via incoming socket packet!")
            wifiDirectManager.markPeerConnectedDirectly(cleanSender)
            emit(MeshEvent.PeerConnected(peerId = cleanSender, groupOwnerIp = null, isGroupOwner = false))
            emit(MeshEvent.ConnectionStateChanged(
                isConnected = true,
                activePeersCount = connectedPeersCount(),
                peerId = cleanSender,
                connectionState = "connected"
            ))
        }
    }

    private fun onSocketPacketReceived(packet: Packet) {
        markPeerConnectedFromSocket(packet.senderId)

        if (packet.packetType == com.meshlink.meshlink.model.PacketType.HANDSHAKE) {
            val cleanSender = packet.senderId.take(8).lowercase()
            Log.i(TAG, "[HANDSHAKE_RECEIVED] Received secret key handshake from peer ${packet.senderId} ($cleanSender)")

            var secretKey = packet.payload
            var peerDisplayName = "Peer $cleanSender"
            var avatarIndex = 0

            try {
                if (packet.payload.trim().startsWith("{")) {
                    val jsonObj = org.json.JSONObject(packet.payload)
                    secretKey = jsonObj.optString("key", packet.payload)
                    peerDisplayName = jsonObj.optString("name", peerDisplayName)
                    avatarIndex = jsonObj.optInt("avatar", 0)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Parsing handshake JSON payload failed: ${e.message}")
            }

            keyManager.registerOrGetPeerKey(packet.senderId, secretKey)
            keyManager.registerOrGetPeerKey(cleanSender, secretKey)

            val updatedEntry = PeerEntry(cleanSender, peerDisplayName, -60, "Wi-Fi Direct")
            peerRegistry.upsert(updatedEntry)
            wifiDirectManager.registerBlePeer(cleanSender, peerDisplayName, null)

            emit(MeshEvent.PeerFound(peerId = cleanSender, peerName = peerDisplayName, rssi = -60))
            connectionAuthenticator.authenticatePeer(packet.senderId, "handshake:${packet.senderId}", packet.signature ?: "")

            // Mutual Handshake Response: ensure the other side receives our handshake packet too!
            if (handshookPeers.add(cleanSender)) {
                Log.i(TAG, "⚡ Replying with mutual HANDSHAKE back to $cleanSender")
                sendHandshakePacket(cleanSender)
            }
            return
        }
        Log.i(TAG, "Received TCP Packet: ${packet.messageId} -> passing to MeshRouter")
        meshRouter.handleIncomingPacket(packet)
    }

    private fun onSocketError(reason: String) {
        Log.e(TAG, "Socket error: $reason")
        emit(MeshEvent.MeshError("SOCKET_ERROR", reason))
    }

    // ── Peer eviction cleanup ──────────────────────────────────────────────────

    private fun scheduleCleanup() {
        val runnable = object : Runnable {
            override fun run() {
                val lost = peerRegistry.evictExpired()
                lost.forEach { emit(MeshEvent.PeerLost(it.peerId)) }
                if (isRunning) handler.postDelayed(this, MeshConstants.CLEANUP_INTERVAL_MS)
            }
        }
        cleanupRunnable = runnable
        handler.postDelayed(runnable, MeshConstants.CLEANUP_INTERVAL_MS)
    }

    private fun cancelCleanup() {
        cleanupRunnable?.let { handler.removeCallbacks(it) }
        cleanupRunnable = null
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private fun emit(event: MeshEvent) {
        handler.post { eventListener?.invoke(event) }
    }

    private fun connectedPeersCount(): Int =
        peerRegistry.all().count { peer ->
            wifiDirectManager.getConnectionState(peer.peerId) == PeerConnectionState.CONNECTED
        }

    /**
     * Extracts a Wi-Fi Direct compatible MAC address from a fallback peer ID.
     * Format: "ble_AABBCCDDEEFF" → "AA:BB:CC:DD:EE:FF"
     */
    private fun deriveMacFromPeerId(peerId: String): String? {
        if (!peerId.startsWith("ble_")) return null
        val hex = peerId.removePrefix("ble_")
        if (hex.length != 12) return null
        return hex.chunked(2).joinToString(":")
    }

    /**
     * Reads a stable node ID from SharedPreferences, or generates and saves a new UUID.
     * Using UUID rather than Android device ID to avoid permission requirements (READ_PHONE_STATE).
     */
    private fun resolveOrGenerateNodeId(): String {
        val prefs: SharedPreferences = context.getSharedPreferences(
            "meshlink_prefs", Context.MODE_PRIVATE
        )
        val existing = prefs.getString("local_node_id", null)
        if (!existing.isNullOrBlank()) return existing
        val generated = UUID.randomUUID().toString().replace("-", "").take(12)
        prefs.edit().putString("local_node_id", generated).apply()
        Log.i(TAG, "Generated new localNodeId: $generated")
        return generated
    }

    /**
     * Checks if Bluetooth adapter is currently enabled on the device.
     */
    fun isBluetoothEnabled(): Boolean {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
        return bluetoothManager?.adapter?.isEnabled == true
    }

    /**
     * Launches system ACTION_REQUEST_ENABLE intent to prompt user to enable Bluetooth.
     */
    fun requestEnableBluetooth(): Boolean {
        return try {
            val intent = android.content.Intent(android.bluetooth.BluetoothAdapter.ACTION_REQUEST_ENABLE).apply {
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch ACTION_REQUEST_ENABLE intent: ${e.message}", e)
            false
        }
    }

    /**
     * Checks if Location Services (GPS / Network provider) are enabled on the device.
     */
    fun isLocationServiceEnabled(): Boolean {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
        return locationManager?.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) == true ||
               locationManager?.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER) == true
    }

    /**
     * Launches system Location Settings page to allow user to enable Location Services.
     */
    fun requestEnableLocationService(): Boolean {
        return try {
            val intent = android.content.Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch ACTION_LOCATION_SOURCE_SETTINGS: ${e.message}", e)
            false
        }
    }
}
