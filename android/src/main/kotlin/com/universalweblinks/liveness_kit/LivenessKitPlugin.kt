package com.universalweblinks.liveness_kit

import android.app.Activity
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/**
 * Registers the two channels the liveness screen needs.
 *
 * Face detection is stateless enough to live on the engine; keeping the
 * screen awake needs the activity's window, so this is [ActivityAware] and
 * holds the activity only while one is attached.
 */
class LivenessKitPlugin : FlutterPlugin, ActivityAware {

    companion object {
        private const val SCREEN_AWAKE_CHANNEL = "com.universalweblinks.liveness_kit/screen_awake"
    }

    private var faceChannel: MethodChannel? = null
    private var screenAwakeChannel: MethodChannel? = null
    private var faceDetector: FaceDetectorPlugin? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val detector = FaceDetectorPlugin(binding.applicationContext)
        faceDetector = detector
        faceChannel = MethodChannel(binding.binaryMessenger, FaceDetectorPlugin.CHANNEL).apply {
            setMethodCallHandler(detector)
        }

        screenAwakeChannel = MethodChannel(binding.binaryMessenger, SCREEN_AWAKE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "setKeepAwake") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val window = activity?.window
                if (window == null) {
                    // No activity to hold the flag on. A screen that dims is a
                    // nuisance, not a failure — never fail the check over it.
                    result.success(null)
                    return@setMethodCallHandler
                }

                // Held on the window, so it lifts on its own if the activity
                // goes away without the Dart side getting to release it.
                if (call.arguments as? Boolean == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        faceChannel?.setMethodCallHandler(null)
        screenAwakeChannel?.setMethodCallHandler(null)
        faceChannel = null
        screenAwakeChannel = null
        faceDetector?.close()
        faceDetector = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
