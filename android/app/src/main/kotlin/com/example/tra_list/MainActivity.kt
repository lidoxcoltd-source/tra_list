package com.example.tra_list

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mjasi/speech_settings")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                } else {
                    try {
                        startActivity(Intent("com.android.settings.TTS_SETTINGS"))
                        result.success("speech")
                    } catch (e: ActivityNotFoundException) {
                        try {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                            result.success("general")
                        } catch (fallback: ActivityNotFoundException) {
                            result.error("unavailable", "Settings are unavailable", null)
                        } catch (fallback: SecurityException) {
                            result.error("denied", "Opening settings was denied", null)
                        }
                    } catch (e: SecurityException) {
                        result.error("denied", "Opening speech settings was denied", null)
                    }
                }
            }
    }
}
