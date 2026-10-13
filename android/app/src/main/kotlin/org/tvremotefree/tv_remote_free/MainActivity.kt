package org.tvremotefree.tv_remote_free

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Android filters incoming multicast (mDNS answers) unless a
        // MulticastLock is held. Held only while a discovery scan runs.
        MethodChannel(messenger, "tv_remote_free/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        val lock = multicastLock ?: (applicationContext
                            .getSystemService(Context.WIFI_SERVICE) as WifiManager)
                            .createMulticastLock("tv_remote_free_discovery")
                            .apply { setReferenceCounted(false) }
                            .also { multicastLock = it }
                        lock.acquire()
                        result.success(null)
                    }
                    "release" -> {
                        multicastLock?.takeIf { it.isHeld }?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Button feedback using the Vibrator's tuned click effects, which are
        // felt on far more phones than View haptic constants.
        MethodChannel(messenger, "tv_remote_free/haptics")
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val v = vibrator
                if (v == null || !v.hasVibrator()) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                play(v, call.arguments as? String ?: "light")
                result.success(null)
            }
    }

    private fun play(v: Vibrator, effect: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val id = when (effect) {
                "tick" -> VibrationEffect.EFFECT_TICK
                "heavy" -> VibrationEffect.EFFECT_HEAVY_CLICK
                "medium" -> VibrationEffect.EFFECT_HEAVY_CLICK
                else -> VibrationEffect.EFFECT_CLICK
            }
            v.vibrate(VibrationEffect.createPredefined(id))
            return
        }
        // Older phones: short one-shot pulses scaled by strength.
        val ms = when (effect) {
            "tick" -> 8L
            "light" -> 15L
            "medium" -> 25L
            else -> 40L
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(ms)
        }
    }

    override fun onDestroy() {
        multicastLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
