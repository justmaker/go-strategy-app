package com.gostratefy.go_strategy_app

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val METHOD_CHANNEL = "com.gostratefy.go_strategy_app/katago"
        private const val EVENT_CHANNEL = "com.gostratefy.go_strategy_app/katago_events"
    }

    private var kataGoEngine: KataGoEngine? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Skip KataGo on emulators to avoid native thread crash
    private val isEmulator by lazy {
        Build.FINGERPRINT.contains("generic") ||
            Build.FINGERPRINT.contains("emulator") ||
            Build.MODEL.contains("Emulator") ||
            Build.PRODUCT.contains("sdk") ||
            Build.HARDWARE.contains("ranchu")
    }

    // Check for devices with known pthread_mutex crash issues
    private fun isProblematicDevice(): Boolean {
        val model = Build.MODEL
        val hardware = Build.HARDWARE
        val platform = Build.BOARD

        // ASUS Zenfone 12 Ultra / Snapdragon 8 Gen 3 / Adreno 750
        return model.contains("ASUS_AI2401") ||
               (hardware == "qcom" && platform == "pineapple")
    }

    private fun ensureKataGoEngine(): Boolean {
        if (kataGoEngine != null) return true
        if (isEmulator) {
            Log.w(TAG, "Emulator detected, skipping KataGo native engine")
            return false
        }

        KataGoEngine.loadNativeLibrary()
        if (KataGoEngine.nativeLoaded) {
            kataGoEngine = KataGoEngine(this)
            kataGoEngine?.setErrorCallback { error ->
                mainHandler.post {
                    eventSink?.success(mapOf(
                        "type" to "error",
                        "message" to error
                    ))
                }
            }
            return true
        } else {
            Log.w(TAG, "KataGo native library unavailable: ${KataGoEngine.nativeLoadError}")
            return false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up Method Channel
        // NOTE: KataGo native library is loaded lazily on first startEngine call
        // to avoid static initializer conflicts with HWUI thread during Activity init
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startEngine" -> {
                    scope.launch(Dispatchers.IO) {
                        // Extreme delay for problematic devices to let GPU/HWUI fully initialize
                        if (isProblematicDevice()) {
                            Log.i(TAG, "Problematic device: waiting 30s before KataGo start")
                            kotlinx.coroutines.delay(30000)
                        }

                        val success = if (ensureKataGoEngine()) {
                            kataGoEngine?.start() ?: false
                        } else {
                            false
                        }
                        withContext(Dispatchers.Main) {
                            result.success(success)
                        }
                    }
                }

                "stopEngine" -> {
                    kataGoEngine?.stop()
                    result.success(true)
                }

                "isEngineRunning" -> {
                    result.success(kataGoEngine?.isEngineRunning() ?: false)
                }

                "analyze" -> {
                    val boardSize = call.argument<Int>("boardSize") ?: 19
                    val moves = call.argument<List<String>>("moves") ?: emptyList()
                    val komi = call.argument<Double>("komi") ?: 7.5
                    val maxVisits = call.argument<Int>("maxVisits") ?: 100

                    val queryId = kataGoEngine?.analyze(
                        boardSize = boardSize,
                        moves = moves,
                        komi = komi,
                        maxVisits = maxVisits
                    ) { response ->
                        mainHandler.post {
                            eventSink?.success(mapOf(
                                "type" to "analysis",
                                "data" to response
                            ))
                        }
                    }

                    result.success(queryId)
                }

                "cancelAnalysis" -> {
                    val queryId = call.argument<String>("queryId")
                    if (queryId != null) {
                        kataGoEngine?.cancelAnalysis(queryId)
                    }
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set up Event Channel for streaming results
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "Event channel listening")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "Event channel cancelled")
                }
            }
        )
    }

    override fun onDestroy() {
        kataGoEngine?.stop()
        scope.cancel()
        super.onDestroy()
    }
}
