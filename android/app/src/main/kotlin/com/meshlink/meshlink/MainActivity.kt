package com.meshlink.meshlink

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.meshlink.meshlink.bridge.MeshMethodChannelHandler
import com.meshlink.meshlink.bridge.MeshEventChannelHandler
import com.meshlink.meshlink.constants.MeshConstants
import com.meshlink.meshlink.mesh.MeshEngine

class MainActivity : FlutterActivity() {
    // MeshEngine is context-dependent — use applicationContext to avoid leaking Activity
    private val meshEngine: MeshEngine by lazy { MeshEngine(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MeshConstants.METHOD_CHANNEL)
            .setMethodCallHandler(MeshMethodChannelHandler(meshEngine))

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MeshConstants.EVENT_CHANNEL)
            .setStreamHandler(MeshEventChannelHandler(meshEngine))
    }

    override fun onDestroy() {
        meshEngine.stopDiscovery()
        super.onDestroy()
    }
}
