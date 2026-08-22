package com.meshlink.meshlink.mesh

import android.util.Log
import com.meshlink.meshlink.model.Packet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap

class SocketManager(
    private val onPacketReceived: (Packet) -> Unit,
    private val onError: (String) -> Unit
) {
    private val TAG = "SocketManager"
    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var serverSocket: ServerSocket? = null
    private var serverJob: kotlinx.coroutines.Job? = null
    private var clientJob: kotlinx.coroutines.Job? = null
    // Socket -> BufferedWriter mapping ensuring 100% atomic socket-writer lifecycle
    private val socketMap = ConcurrentHashMap<Socket, BufferedWriter>()

    @Volatile
    private var isIntentionalDisconnect = false
    private var lastTargetIp: String? = null
    private var lastTargetPort: Int? = null

    companion object {
        const val MAX_RECONNECT_ATTEMPTS = 30
        const val INITIAL_BACKOFF_MS = 250L
        const val BACKOFF_MULTIPLIER = 1.25
        const val MAX_BACKOFF_MS = 1500L
    }

    @Synchronized
    fun startServer(port: Int) {
        if (serverSocket != null && !serverSocket!!.isClosed && serverSocket!!.isBound) {
            Log.i(TAG, "ServerSocket is already active and bound on port $port — keeping active listener")
            return
        }

        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null

        isIntentionalDisconnect = false
        if (!scope.isActive) {
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        }

        serverJob?.cancel()
        serverJob = scope.launch {
            try {
                val ss = ServerSocket()
                ss.reuseAddress = true
                ss.bind(java.net.InetSocketAddress(port))
                serverSocket = ss
                Log.i(TAG, "ServerSocket started on port $port")
                while (isActive && !isIntentionalDisconnect) {
                    val clientSocket = serverSocket?.accept() ?: break
                    Log.i(TAG, "Client connected to ServerSocket: ${clientSocket.remoteSocketAddress}")
                    handleSocketRead(clientSocket, isClient = false)
                }
            } catch (e: Exception) {
                if (scope.isActive && !isIntentionalDisconnect && e.message?.contains("closed", ignoreCase = true) != true) {
                    Log.w(TAG, "ServerSocket notice on port $port: ${e.message}")
                }
            }
        }
    }

    @Synchronized
    fun connectToServer(
        ip: String,
        port: Int,
        maxRetries: Int = MAX_RECONNECT_ATTEMPTS,
        initialBackoffMs: Long = INITIAL_BACKOFF_MS
    ) {
        isIntentionalDisconnect = false
        if (!scope.isActive) {
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        }
        lastTargetIp = ip
        lastTargetPort = port

        // Prune any dead/closed sockets first
        pruneDeadSockets()

        // Check if we already have an active connected socket to target IP
        val alreadyConnected = socketMap.keys.any { socket ->
            !socket.isClosed && socket.isConnected && socket.inetAddress?.hostAddress == ip
        }
        if (alreadyConnected) {
            Log.i(TAG, "Already have an active socket connected to $ip:$port — skipping duplicate connectToServer")
            return
        }

        clientJob?.cancel()
        clientJob = scope.launch {
            var currentBackoff = initialBackoffMs
            var attempt = 0
            var connectedSocket: Socket? = null

            while (isActive && attempt < maxRetries && !isIntentionalDisconnect) {
                attempt++
                try {
                    Log.i(TAG, "[RECONNECT_ATTEMPT] Connecting to $ip:$port (Attempt $attempt/$maxRetries, backoff=${currentBackoff}ms)")
                    val socket = Socket()
                    socket.reuseAddress = true
                    socket.tcpNoDelay = true
                    socket.connect(java.net.InetSocketAddress(ip, port), 4000)
                    connectedSocket = socket
                    Log.i(TAG, "Connected successfully to $ip:$port")
                    break
                } catch (e: Exception) {
                    Log.w(TAG, "Connect attempt $attempt failed to $ip:$port: ${e.message}")
                    if (attempt >= maxRetries) {
                        onError("Failed to connect to $ip:$port after $maxRetries attempts: ${e.message}")
                        return@launch
                    }
                    delay(currentBackoff)
                    currentBackoff = (currentBackoff * BACKOFF_MULTIPLIER).toLong().coerceAtMost(MAX_BACKOFF_MS)
                }
            }

            connectedSocket?.let { handleSocketRead(it, isClient = true) }
        }
    }

    var onSocketConnected: (() -> Unit)? = null
    var onSocketDisconnected: (() -> Unit)? = null

    private fun handleSocketRead(socket: Socket, isClient: Boolean) {
        scope.launch {
            var unexpectedDrop = false
            try {
                val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
                val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
                socketMap[socket] = writer
                Log.i(TAG, "Socket registered in socketMap (total active=${socketMap.size}, isClient=$isClient)")
                onSocketConnected?.invoke()

                while (isActive && !socket.isClosed && !isIntentionalDisconnect) {
                    val line = reader.readLine()
                    if (line == null) {
                        Log.w(TAG, "EOF on socket $socket — connection dropped unexpectedly")
                        unexpectedDrop = true
                        break
                    }
                    if (line.isBlank()) continue

                    try {
                        val packet = Packet.fromJson(line)
                        Log.d(TAG, "Received packet: ${packet.messageId} from ${packet.senderId}")
                        onPacketReceived(packet)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to parse incoming packet JSON: ${e.message}. Raw line: $line")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Socket read error: ${e.message}")
                unexpectedDrop = true
            } finally {
                cleanupSocket(socket)
                if (isClient && unexpectedDrop && !isIntentionalDisconnect && lastTargetIp != null && lastTargetPort != null) {
                    Log.i(TAG, "Unexpected drop — initiating reconnection to ${lastTargetIp}:${lastTargetPort}")
                    connectToServer(lastTargetIp!!, lastTargetPort!!)
                }
            }
        }
    }

    suspend fun sendPacket(packet: Packet, exceptHop: String? = null): Boolean = withContext(Dispatchers.IO) {
        pruneDeadSockets()

        if (socketMap.isEmpty()) {
            Log.e(TAG, "sendPacket failed for messageId=${packet.messageId}: No active socket connections available")
            return@withContext false
        }

        val jsonStr = packet.toJson()
        val line = "$jsonStr\n"
        var successCount = 0

        val iterator = socketMap.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            val socket = entry.key
            val writer = entry.value

            if (socket.isClosed || !socket.isConnected) {
                iterator.remove()
                try { socket.close() } catch (_: Exception) {}
                continue
            }

            try {
                writer.write(line)
                writer.flush()
                successCount++
                Log.i(TAG, "Packet ${packet.messageId} sent successfully over socket ${socket.remoteSocketAddress}")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending packet over socket ${socket.remoteSocketAddress}: ${e.message} — removing dead socket")
                iterator.remove()
                try { socket.close() } catch (_: Exception) {}
            }
        }

        return@withContext successCount > 0
    }

    private fun pruneDeadSockets() {
        val iterator = socketMap.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            val socket = entry.key
            if (socket.isClosed || !socket.isConnected) {
                iterator.remove()
                try { socket.close() } catch (_: Exception) {}
            }
        }
    }

    private fun cleanupSocket(socket: Socket) {
        try {
            socketMap.remove(socket)
            socket.close()
            Log.i(TAG, "Cleaned up socket ${socket.remoteSocketAddress} (remaining active=${socketMap.size})")
            if (socketMap.isEmpty()) {
                onSocketDisconnected?.invoke()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error closing socket: ${e.message}")
        }
    }

    @Synchronized
    fun stopAll(keepIntentionalFlag: Boolean = false) {
        if (!keepIntentionalFlag) {
            isIntentionalDisconnect = true
        }
        try {
            scope.coroutineContext.cancelChildren()
        } catch (_: Exception) {}
        try {
            serverSocket?.close()
            serverSocket = null
        } catch (e: Exception) {
            Log.w(TAG, "Error closing server socket: ${e.message}")
        }

        val iterator = socketMap.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            try {
                entry.key.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing socket: ${e.message}")
            }
            iterator.remove()
        }
        Log.i(TAG, "SocketManager stopped all sockets (intentional=$isIntentionalDisconnect)")
    }
}
