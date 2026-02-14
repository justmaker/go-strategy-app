package com.gostratefy.go_strategy_app

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.*

/**
 * KataGo Engine wrapper for Android (ONNX Backend, Single-threaded).
 * Uses synchronous JNI API - no pthread, no pipe.
 */
class KataGoEngine(private val context: Context) {
    // New JNI Native Methods (synchronous)
    private external fun initializeNative(
        config: String,
        modelBin: String,
        modelOnnx: String,
        boardSize: Int
    ): Boolean

    private external fun analyzePositionNative(
        boardXSize: Int,
        boardYSize: Int,
        komi: Double,
        maxVisits: Int,
        moves: Array<Array<String>>  // [["B","Q16"],["W","D4"],...]
    ): String  // Returns JSON result

    private external fun destroyNative()

    companion object {
        private const val TAG = "KataGoEngine"
        private const val MODEL_BIN_FILE = "model.bin.gz"

        var nativeLoaded = false
            private set
        var nativeLoadError: String? = null
            private set

        fun loadNativeLibrary() {
            if (nativeLoaded) return
            try {
                System.loadLibrary("katago_mobile")
                nativeLoaded = true
                Log.i(TAG, "✓ Native library loaded (ONNX backend)")
            } catch (e: UnsatisfiedLinkError) {
                nativeLoadError = e.message
                Log.e(TAG, "Failed to load native library: ${e.message}")
            }
        }
    }

    private var isInitialized = false
    private var initializedBoardSize = 0

    /**
     * Initialize KataGo engine for a specific board size.
     */
    suspend fun start(boardSize: Int = 19): Boolean = withContext(Dispatchers.IO) {
        if (isInitialized && initializedBoardSize == boardSize) return@withContext true

        // Re-initialize if board size changed
        if (isInitialized && initializedBoardSize != boardSize) {
            Log.i(TAG, "Board size changed: ${initializedBoardSize} -> ${boardSize}, reinitializing...")
            destroyNative()
            isInitialized = false
            initializedBoardSize = 0
        }

        if (!nativeLoaded) {
            Log.e(TAG, "Cannot start: native library not loaded (${nativeLoadError})")
            return@withContext false
        }

        try {
            // Extract model files
            val modelBinPath = extractAsset("katago/$MODEL_BIN_FILE")
                ?: return@withContext false

            // Load board-size-specific ONNX model
            val modelOnnxPath = extractAsset("katago/model_${boardSize}x${boardSize}.onnx")
                ?: extractAsset("katago/model.onnx")
                ?: return@withContext false

            val configPath = createConfigFile()

            Log.i(TAG, "Initializing KataGo (ONNX backend) for ${boardSize}x${boardSize}...")
            val success = initializeNative(configPath, modelBinPath, modelOnnxPath, boardSize)

            if (success) {
                isInitialized = true
                initializedBoardSize = boardSize
                Log.i(TAG, "✓ KataGo initialized for ${boardSize}x${boardSize}")
                return@withContext true
            } else {
                Log.e(TAG, "❌ KataGo initialization failed")
                return@withContext false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Initialization error", e)
            return@withContext false
        }
    }

    /**
     * Stop and cleanup KataGo engine.
     */
    fun stop() {
        if (!isInitialized) return
        destroyNative()
        isInitialized = false
        Log.i(TAG, "✓ KataGo destroyed")
    }

    /**
     * Analyze a position (synchronous, blocking call).
     * Automatically reinitializes if board size changed.
     */
    suspend fun analyze(
        boardSize: Int,
        moves: List<String>,
        komi: Double,
        maxVisits: Int
    ): String = withContext(Dispatchers.IO) {
        // Ensure engine is initialized for the correct board size
        if (!isInitialized || initializedBoardSize != boardSize) {
            val started = start(boardSize)
            if (!started) {
                return@withContext "{\"error\": \"Failed to initialize engine for ${boardSize}x${boardSize}\"}"
            }
        }

        try {
            Log.d(TAG, "Analyzing: ${boardSize}x${boardSize}, ${moves.size} moves, komi=$komi, visits=$maxVisits")

            // Convert moves format: ["B Q16", "W D4"] -> [["B","Q16"],["W","D4"]]
            val movesArray = moves.map { move ->
                val parts = move.trim().split(" ", limit = 2)
                if (parts.size == 2) {
                    arrayOf(parts[0], parts[1])
                } else {
                    arrayOf("B", "pass")  // Fallback
                }
            }.toTypedArray()

            // Synchronous JNI call (blocks until analysis complete)
            val result = analyzePositionNative(
                boardSize, boardSize,
                komi, maxVisits,
                movesArray
            )

            Log.d(TAG, "✓ Analysis completed: ${result.length} bytes")
            return@withContext result

        } catch (e: Exception) {
            Log.e(TAG, "Analysis exception", e)
            return@withContext "{\"error\": \"${e.message}\"}"
        }
    }

    /**
     * Check if engine is running.
     */
    fun isEngineRunning(): Boolean = isInitialized

    // Helper methods

    private fun extractAsset(assetPath: String): String? {
        val filename = assetPath.substringAfterLast('/')
        val outputFile = File(context.cacheDir, filename)

        // Check if already extracted
        if (outputFile.exists() && outputFile.length() > 0) {
            Log.d(TAG, "Asset cached: $assetPath")
            return outputFile.absolutePath
        }

        // Try multiple asset path variants
        val paths = listOf(
            "flutter_assets/assets/$assetPath",
            "flutter_assets/$assetPath",
            assetPath
        )

        for (path in paths) {
            try {
                context.assets.open(path).use { input ->
                    FileOutputStream(outputFile).use { output ->
                        input.copyTo(output)
                    }
                }
                Log.i(TAG, "✓ Asset extracted: $path -> ${outputFile.absolutePath}")
                return outputFile.absolutePath
            } catch (e: Exception) {
                // Try next path
            }
        }

        Log.e(TAG, "❌ Failed to extract asset: $assetPath")
        return null
    }

    private fun createConfigFile(): String {
        val configFile = File(context.cacheDir, "analysis.cfg")

        val config = """
            # KataGo Analysis Config for Android (Single-threaded)

            # Single-threaded configuration (avoid pthread)
            numSearchThreads = 1
            numAnalysisThreads = 1
            numNNServerThreadsPerModel = 1

            # Visits
            maxVisits = 100

            # Output format
            reportAnalysisWinratesAs = BLACK

            # Cache (mutex locks are OK, pthread_create is not)
            nnCacheSizePowerOfTwo = 18
            nnMutexPoolSizePowerOfTwo = 14

            # Batch size
            nnMaxBatchSize = 1

            # Logging
            logSearchInfo = false
            logToStderr = false
        """.trimIndent()

        configFile.writeText(config)
        return configFile.absolutePath
    }
}
