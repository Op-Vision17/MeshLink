package com.meshlink.meshlink.mesh

class SocketClient(private val socketManager: SocketManager) {
    fun connect(ip: String, port: Int) {
        socketManager.connectToServer(ip, port)
    }

    fun stop() {
        socketManager.stopAll()
    }
}
