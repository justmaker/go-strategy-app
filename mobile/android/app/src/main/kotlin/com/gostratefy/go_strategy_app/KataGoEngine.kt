package com.gostratefy.go_strategy_app

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * KataGo Engine wrapper for Android.
 * Manages the KataGo process and communicates via GTP/Analysis protocol.
 */
class KataGoEngine(private val context: Context) {
    // JNI Native Methods
    private external fun startNative(config: String, model: String): Boolean
    private external fun writeToProcess(data: String)
    private external fun readFromProcess(): String
    private external fun stopNative()

    companion object {
        init {
            System.loadLibrary("katago_mobile")
        }
        private const val TAG = "KataGoEngine"
        private const val MODEL_FILE = "model.bin.gz"
    }

    private val isRunning = AtomicBoolean(false)
    private val isReaderActive = AtomicBoolean(false)
    private val queryId = AtomicInteger(0)
    private var scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // Callbacks
    private var analysisCallback: ((String) -> Unit)? = null
    private var errorCallback: ((String) -> Unit)? = null

    /**
     * Initialize and start the KataGo engine via JNI.
     */
    suspend fun start(): Boolean = withContext(Dispatchers.IO) {
        if (isRunning.get()) return@withContext true

        try {
            val modelPath = extractModel() ?: return@withContext false
            val configPath = createConfigFile()

            Log.i(TAG, "Starting Native KataGo...")
            val success = startNative(configPath, modelPath)

            if (success) {
                startOutputReaders()

                val ready = waitForReady(timeoutMs = 30000)
                if (ready) {
                    isRunning.set(true)
                    Log.i(TAG, "Native KataGo started and ready")
                    return@withContext true
                } else {
                    Log.e(TAG, "KataGo readiness probe timed out")
                    isReaderActive.set(false)
                    stopNative()
                    return@withContext false
                }
            } else {
                Log.e(TAG, "Failed to start Native KataGo")
                return@withContext false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Start Native Error", e)
            return@withContext false
        }
    }

    private suspend fun waitForReady(timeoutMs: Long): Boolean {
        val deferred = CompletableDeferred<Boolean>()
        val previousCallback = analysisCallback

        analysisCallback = { line ->
            if (line.contains("probe_ready")) {
                deferred.complete(true)
            }
        }

        try {
            val probe = JSONObject().apply {
                put("id", "probe_ready")
                put("boardXSize", 9)
                put("boardYSize", 9)
                put("komi", 5.5)
                put("maxVisits", 1)
                put("moves", JSONArray())
            }
            Log.d(TAG, "Sending readiness probe...")
            writeToProcess(probe.toString())

            return withTimeoutOrNull(timeoutMs) { deferred.await() } ?: false
        } catch (e: Exception) {
            Log.e(TAG, "Readiness probe failed", e)
            return false
        } finally {
            analysisCallback = previousCallback
        }
    }

    fun stop() {
        if (!isRunning.get()) return
        stopNative()
        isRunning.set(false)
        isReaderActive.set(false)
        scope.cancel()
        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    }


    /**
     * Analyze a position.
     */
    /**
     * Analyze a position.
     */
    fun analyze(
        boardSize: Int,
        moves: List<String>,
        komi: Double,
        maxVisits: Int,
        callback: (String) -> Unit
    ): String {
        if (!isRunning.get()) {
            callback("{\"error\": \"Engine not running\"}")
            return ""
        }

        val id = "q${queryId.incrementAndGet()}"
        analysisCallback = callback

        try {
            val query = buildAnalysisQuery(id, boardSize, moves, komi, maxVisits)
            Log.d(TAG, "Sending query: $query")
            
            writeToProcess(query)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send query", e)
            callback("{\"error\": \"${e.message}\"}")
        }

        return id
    }

    /**
     * Cancel ongoing analysis.
     */
    fun cancelAnalysis(queryId: String) {
        if (!isRunning.get()) return

        try {
            val cmd = JSONObject().apply {
                put("id", "cancel_$queryId")
                put("action", "terminate")
                put("terminateId", queryId)
            }
            writeToProcess(cmd.toString())
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cancel analysis", e)
        }
    }

    /**
     * Check if engine is running.
     */
    fun isEngineRunning(): Boolean = isRunning.get()

    /**
     * Set error callback.
     */
    fun setErrorCallback(callback: (String) -> Unit) {
        errorCallback = callback
    }

    // Private methods

    private fun extractModel(): String? {
        val modelFile = File(context.cacheDir, MODEL_FILE)

        // Check if already extracted
        if (modelFile.exists() && modelFile.length() > 0) {
            return modelFile.absolutePath
        }

        // Flutter assets are stored under flutter_assets/assets/ in the APK
        val assetPaths = listOf(
            "flutter_assets/assets/katago/$MODEL_FILE",
            "katago/$MODEL_FILE",
        )

        for (assetPath in assetPaths) {
            try {
                context.assets.open(assetPath).use { input ->
                    FileOutputStream(modelFile).use { output ->
                        input.copyTo(output)
                    }
                }
                Log.i(TAG, "Model extracted from $assetPath to ${modelFile.absolutePath}")
                return modelFile.absolutePath
            } catch (e: Exception) {
                Log.d(TAG, "Asset not found at $assetPath, trying next...")
            }
        }

        Log.e(TAG, "Failed to extract model from any asset path")
        return null
    }

    private fun createConfigFile(): String {
        val configFile = File(context.cacheDir, "analysis.cfg")
        
        val config = """
            # KataGo Analysis Config for Android
            
            # Limits
            maxVisits = 100
            numSearchThreads = 2
            
            # Analysis output
            reportAnalysisWinratesAs = BLACK
            
            # Performance tuning for mobile
            nnCacheSizePowerOfTwo = 18
            nnMutexPoolSizePowerOfTwo = 14
            numNNServerThreadsPerModel = 1
            
            # Disable features not needed for analysis
            logSearchInfo = false
            logToStderr = true
        """.trimIndent()

        configFile.writeText(config)
        return configFile.absolutePath
    }

    private fun buildAnalysisQuery(
        id: String,
        boardSize: Int,
        moves: List<String>,
        komi: Double,
        maxVisits: Int
    ): String {
        val query = JSONObject().apply {
            put("id", id)
            put("boardXSize", boardSize)
            put("boardYSize", boardSize)
            put("komi", komi)
            put("maxVisits", maxVisits)
            put("reportDuringSearchEvery", 1.0)  // Report progress
            
            // Convert moves to array format
            val movesArray = JSONArray()
            for (move in moves) {
                val parts = move.split(" ")
                if (parts.size == 2) {
                    val moveArr = JSONArray()
                    moveArr.put(parts[0])  // Color: B or W
                    moveArr.put(parts[1])  // Coordinate: e.g., Q16
                    movesArray.put(moveArr)
                }
            }
            put("moves", movesArray)
        }
        
        return query.toString()
    }

    private fun startOutputReaders() {
        isReaderActive.set(true)
        // Read stdout (analysis results) from Native via JNI
        scope.launch {
            Log.i(TAG, "Starting Output Reader Loop")
            while (isReaderActive.get()) {
                try {
                    // Blocking read from native pipe
                    val line = readFromProcess()
                    if (line.isNotEmpty()) {
                        Log.d(TAG, "KataGo stdout: $line")
                        processOutput(line)
                    } else {
                        // Empty line might mean EOF or just empty flush?
                        // Yield to prevent tight loop if non-blocking (though native is blocking)
                        yield()
                    }
                } catch (e: Exception) {
                    if (isReaderActive.get()) {
                        Log.e(TAG, "Error reading from process", e)
                    }
                    delay(100) // Backoff on error
                }
            }
            Log.i(TAG, "Output Reader Loop Ended")
        }

        // Standard error is not captured in current Native impl
        // If needed, we would add another pipe in native-lib.cpp
    }

    private fun processOutput(line: String) {
        try {
            val json = JSONObject(line)
            
            // Check if this is a final result or progress update
            val isDuringSearch = json.optBoolean("isDuringSearch", false)
            
            // Always forward to callback
            analysisCallback?.invoke(line)
            
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse output: $line", e)
        }
    }
}
