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
    companion object {
        private const val TAG = "KataGoEngine"
        private const val KATAGO_BINARY = "libkatago.so"
        private const val MODEL_FILE = "model.bin.gz"
    }

    private var process: Process? = null
    private var stdin: BufferedWriter? = null
    private var stdout: BufferedReader? = null
    private var stderr: BufferedReader? = null
    
    private val isRunning = AtomicBoolean(false)
    private val queryId = AtomicInteger(0)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // Callbacks
    private var analysisCallback: ((String) -> Unit)? = null
    private var errorCallback: ((String) -> Unit)? = null

    /**
     * Initialize and start the KataGo engine.
     */
    suspend fun start(): Boolean = withContext(Dispatchers.IO) {
        if (isRunning.get()) {
            Log.w(TAG, "Engine already running")
            return@withContext true
        }

        try {
            // Get paths
            val nativeLibDir = context.applicationInfo.nativeLibraryDir
            val katagoPath = "$nativeLibDir/$KATAGO_BINARY"
            
            // Extract model to cache dir if needed
            val modelPath = extractModel()
            if (modelPath == null) {
                Log.e(TAG, "Failed to extract model")
                return@withContext false
            }
            
            // Create config file
            val configPath = createConfigFile()
            
            Log.i(TAG, "Starting KataGo: $katagoPath")
            Log.i(TAG, "Model: $modelPath")
            Log.i(TAG, "Config: $configPath")
            
            // Start process
            val pb = ProcessBuilder(
                katagoPath,
                "analysis",
                "-config", configPath,
                "-model", modelPath
            )
            pb.directory(context.cacheDir)
            pb.environment()["LD_LIBRARY_PATH"] = nativeLibDir
            
            process = pb.start()
            stdin = process!!.outputStream.bufferedWriter()
            stdout = process!!.inputStream.bufferedReader()
            stderr = process!!.errorStream.bufferedReader()
            
            isRunning.set(true)
            
            // Start reading stdout and stderr
            startOutputReaders()
            
            // Wait a bit for startup
            delay(500)
            
            Log.i(TAG, "KataGo started successfully")
            return@withContext true
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start KataGo", e)
            errorCallback?.invoke("Failed to start engine: ${e.message}")
            return@withContext false
        }
    }

    /**
     * Stop the KataGo engine.
     */
    fun stop() {
        if (!isRunning.get()) return
        
        try {
            // Send quit command
            stdin?.write("{\"id\":\"quit\",\"action\":\"terminate\"}\n")
            stdin?.flush()
            
            // Wait briefly then force kill
            Thread.sleep(500)
            process?.destroyForcibly()
            
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping engine", e)
        } finally {
            process = null
            stdin = null
            stdout = null
            stderr = null
            isRunning.set(false)
            scope.cancel()
        }
    }

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
            
            stdin?.write(query + "\n")
            stdin?.flush()
            
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
            stdin?.write(cmd.toString() + "\n")
            stdin?.flush()
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

        try {
            context.assets.open("katago/$MODEL_FILE").use { input ->
                FileOutputStream(modelFile).use { output ->
                    input.copyTo(output)
                }
            }
            Log.i(TAG, "Model extracted to ${modelFile.absolutePath}")
            return modelFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract model", e)
            return null
        }
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
            logToStderr = false
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
        // Read stdout (analysis results)
        scope.launch {
            try {
                stdout?.forEachLine { line ->
                    if (line.isNotBlank()) {
                        Log.d(TAG, "KataGo stdout: $line")
                        processOutput(line)
                    }
                }
            } catch (e: Exception) {
                if (isRunning.get()) {
                    Log.e(TAG, "Error reading stdout", e)
                }
            }
        }

        // Read stderr (logs/errors)
        scope.launch {
            try {
                stderr?.forEachLine { line ->
                    if (line.isNotBlank()) {
                        Log.d(TAG, "KataGo stderr: $line")
                        // Check for fatal errors
                        if (line.contains("error", ignoreCase = true) || 
                            line.contains("failed", ignoreCase = true)) {
                            errorCallback?.invoke(line)
                        }
                    }
                }
            } catch (e: Exception) {
                if (isRunning.get()) {
                    Log.e(TAG, "Error reading stderr", e)
                }
            }
        }
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
