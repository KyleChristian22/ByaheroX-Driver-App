package com.byaherox.commuter

import android.content.Intent
import android.nfc.NfcAdapter
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val deviceSettingsChannel = "byaherox/device_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceSettingsChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNfcStatus" -> {
                    val adapter = NfcAdapter.getDefaultAdapter(this)
                    result.success(
                        mapOf(
                            "supported" to (adapter != null),
                            "enabled" to (adapter?.isEnabled == true)
                        )
                    )
                }
                "openNfcSettings" -> {
                    val intent = Intent(Settings.ACTION_NFC_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
