package com.meshlink.meshlink.mesh

class SocketServer(private val socketManager: SocketManager) {
    fun start(port: Int) {
        socketManager.startServer(port)
    }

    fun stop() {
        socketManager.stopAll()
    }
}
