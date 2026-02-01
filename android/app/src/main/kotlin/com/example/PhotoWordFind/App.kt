package com.example.PhotoWordFind

import android.util.Log
import dev.fluttercommunity.workmanager.WorkmanagerPlugin
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugins.GeneratedPluginRegistrant

class App : FlutterApplication(), PluginRegistry.PluginRegistrantCallback {
    override fun onCreate() {
        super.onCreate()
        WorkmanagerPlugin.setPluginRegistrantCallback(this)
    }

    override fun registerWith(registry: PluginRegistry) {
        val engine = extractFlutterEngine(registry)
        if (engine == null) {
            Log.e(TAG, "Unable to locate FlutterEngine for background plugin registration.")
            return
        }
        try {
            GeneratedPluginRegistrant.registerWith(engine)
        } catch (e: Exception) {
            Log.e(TAG, "GeneratedPluginRegistrant failed to register plugins", e)
        }
    }

    private fun extractFlutterEngine(registry: PluginRegistry): FlutterEngine? {
        return try {
            val field = registry.javaClass.getDeclaredField("flutterEngine")
            field.isAccessible = true
            field.get(registry) as? FlutterEngine
        } catch (e: Exception) {
            Log.e(TAG, "Failed to access flutterEngine from PluginRegistry", e)
            null
        }
    }

    companion object {
        private const val TAG = "App"
    }
}
