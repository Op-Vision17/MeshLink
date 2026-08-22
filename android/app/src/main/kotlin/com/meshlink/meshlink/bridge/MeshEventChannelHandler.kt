package com.meshlink.meshlink.bridge

import com.meshlink.meshlink.mesh.MeshEngine
import io.flutter.plugin.common.EventChannel

class MeshEventChannelHandler(private val engine: MeshEngine) : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        engine.setEventListener { meshEvent ->
            eventSink?.success(meshEvent.toMap())
        }
    }

    override fun onCancel(arguments: Any?) {
        engine.setEventListener(null)
        eventSink = null
    }
}
