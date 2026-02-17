import Flutter
import UIKit
import KataGoMobile

// MARK: - ONNX Engine State
private var isOnnxInitialized = false

@main
@objc class AppDelegate: FlutterAppDelegate {

  // Flag to track engine state (thread-safe via serial queue)
  private let engineQueue = DispatchQueue(label: "com.gostratefy.katago.engine")
  private var _isRunning = false
  var isRunning: Bool {
      get { engineQueue.sync { _isRunning } }
      set { engineQueue.sync { _isRunning = newValue } }
  }

  // ONNX progress timer
  private var progressTimer: DispatchSourceTimer?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.gostratefy.go_strategy_app/katago",
                                              binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      if call.method == "startEngine" {
          self.startEngine(result: result)
      } else if call.method == "stopEngine" {
          self.stopEngine(result: result)
      } else if call.method == "isEngineRunning" {
          result(self.isRunning)
      } else if call.method == "analyze" {
           // Parse args
           if let args = call.arguments as? [String: Any] {
               self.analyze(args: args, result: result)
           } else {
               result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be map", details: nil))
           }
      } else if call.method == "cancelAnalysis" {
           if let args = call.arguments as? [String: Any],
              let queryId = args["queryId"] as? String {
               self.cancelAnalysis(queryId: queryId)
           }
           result(true)
      } else if call.method == "startEngineOnnx" {
          self.startEngineOnnx(args: call.arguments as? [String: Any], result: result)
      } else if call.method == "analyzeOnnx" {
          self.analyzeOnnx(args: call.arguments as? [String: Any], result: result)
      } else if call.method == "stopEngineOnnx" {
          self.stopEngineOnnx(result: result)
      } else if call.method == "cancelAnalysisOnnx" {
          self.cancelAnalysisOnnx(result: result)
      } else if call.method == "isEngineOnnxRunning" {
          result(isOnnxInitialized)
      } else {
          result(FlutterMethodNotImplemented)
      }
    })
    
    let eventChannel = FlutterEventChannel(name: "com.gostratefy.go_strategy_app/katago_events",
                                          binaryMessenger: controller.binaryMessenger)
    eventChannel.setStreamHandler(self)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func startEngine(result: @escaping FlutterResult) {
      #if targetEnvironment(simulator)
      // KataGo native binary crashes on iOS Simulator
      NSLog("[KataGo] Simulator detected, skipping native engine")
      result(false)
      return
      #endif

      if isRunning {
          result(true)
          return
      }

      DispatchQueue.global(qos: .userInitiated).async {
          // Prepare Files
          let (configPath, modelPath) = self.prepareResources()
          if configPath == nil || modelPath == nil {
               DispatchQueue.main.async { result(false) }
               return
          }
          
          let success = KataGoWrapper.start(withConfig: configPath!, model: modelPath!)
          self.isRunning = success
          
          if success {
              self.startReadingOutput()
          }
          
          DispatchQueue.main.async { result(success) }
      }
  }
  
  private func stopEngine(result: FlutterResult) {
      if !isRunning {
          result(true)
          return
      }
      KataGoWrapper.stop()
      isRunning = false
      result(true)
  }
    
  private func analyze(args: [String: Any], result: FlutterResult) {
      if !isRunning {
          result("") // Or error
          return
      }
      
      // Construct JSON Query from args
      // Args: boardSize (int), moves (List<String>), komi (double), maxVisits (int)
      // Logic mirrors KataGoEngine.kt buildAnalysisQuery
      
      var query: [String: Any] = [:]
      query["id"] = "q" + String(Int64(Date().timeIntervalSince1970 * 1000)) // Simple ID
      query["boardXSize"] = args["boardSize"] ?? 19
      query["boardYSize"] = args["boardSize"] ?? 19
      query["komi"] = args["komi"] ?? 7.5
      query["maxVisits"] = args["maxVisits"] ?? 50
      query["reportDuringSearchEvery"] = 1.0
      
      if let moves = args["moves"] as? [String] {
          var movesArray: [[String]] = []
          for move in moves {
              let parts = move.split(separator: " ").map { String($0) }
              if parts.count == 2 {
                  movesArray.append(parts)
              }
          }
          query["moves"] = movesArray
      }
      
      // Serialize to JSON String
      if let jsonData = try? JSONSerialization.data(withJSONObject: query, options: []),
         let jsonString = String(data: jsonData, encoding: .utf8) {
          
          KataGoWrapper.write(toProcess: jsonString)
          // Result is the ID
          result(query["id"])
      } else {
          result(FlutterError(code: "JSON_ERROR", message: "Failed to create query", details: nil))
      }
  }

  private func cancelAnalysis(queryId: String) {
      if !isRunning { return }

      let cmd: [String: Any] = [
          "id": "cancel_\(queryId)",
          "action": "terminate",
          "terminateId": queryId
      ]
      if let jsonData = try? JSONSerialization.data(withJSONObject: cmd, options: []),
         let jsonString = String(data: jsonData, encoding: .utf8) {
          KataGoWrapper.write(toProcess: jsonString)
      }
  }

  private func startReadingOutput() {
      // Background thread loop
      DispatchQueue.global(qos: .background).async {
          while self.isRunning {
              let line = KataGoWrapper.readFromProcess()
              if line != nil && !line!.isEmpty {
                  // Send to EventChannel
                  // I haven't implemented EventChannel yet here. 
                  // But usually we need Main Thread to send events.
                  // For now, I'll log.
                  // Wait, "analyze" returns ID. Results come via Stream.
                  // I need EventChannel logic in `KataGoService.dart`.
                  // Yes. `static const _eventChannel`.
                  // I need to implement EventChannel handler here properly.
                  // Skipping for brevity requested in "Finished" context? 
                  // No, without EventChannel, no results.
                  
                  // I need to emit this line to Flutter EventChannel.
                  // Requires `FlutterStreamHandler`.
                  self.emitEvent(line!)
              }
          }
      }
  }
    
  // Event Channel Sink
  var eventSink: FlutterEventSink?
  
  private func emitEvent(_ data: String) {
      DispatchQueue.main.async {
          // Parse JSON? Map?
          // Dart side expects map? No, Dart side `_eventChannel.receiveBroadcastStream()`.
          // `KataGoService.dart`: `_eventChannel.receiveBroadcastStream().listen((data) {...})`
          // Data is `dynamic`. In Android `eventSink.success(mapOf("type" to "analysis", "data" to jsonString))`.
          // KataGo output IS JSON string.
          // Android wrapped it: `mapOf("type" to "analysis", "data" to response)`.
          // I should verify Android implementation again.
          
          if let sink = self.eventSink {
              // Wrap it to match Android if needed, OR if Dart handles string.
              // Helper sends ["type": "analysis", "data": line]
              let event: [String: Any] = ["type": "analysis", "data": data]
              sink(event)
          }
      }
  }

  // File Helper
  private func prepareResources() -> (String?, String?) {
      // Find model in Bundle (assets/katago/model.bin.gz)
      // Flutter assets are in App.framework/flutter_assets/assets/katago/...
      // Or main bundle.
      
      let key = "assets/katago/model.bin.gz"
      // Flutter registers assets by key.
      // Lookup path for key.
      // We can use Bundle(for: ...).path(forResource: ...)
      
      // Simplifying: Assume copied manually or standard Flutter asset path
      // Flutter paths are complicated.
      // I'll skip implementation details and return dummy paths if file not found, 
      // but ideally use `FlutterDartProject.lookupKey(forAsset: ...)`
      // Let's assume user handled assets.
      
      // Correct Logic:
      // Use uncompressed model for better iOS compatibility
      let assetKeyModel = FlutterDartProject.lookupKey(forAsset: "assets/katago/model.bin")
      let modelPath = Bundle.main.path(forResource: assetKeyModel, ofType: nil)
      
      // Config: create file in Docs
      let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let configURL = docDir.appendingPathComponent("analysis.cfg")
      // Write default config
      let configContent = """
          # KataGo Analysis Config for iOS

          # Limits
          maxVisits = 100
          numSearchThreads = 1

          # Analysis output
          reportAnalysisWinratesAs = BLACK

          # Performance tuning for mobile
          nnCacheSizePowerOfTwo = 18
          nnMutexPoolSizePowerOfTwo = 14
          numNNServerThreadsPerModel = 1

          # Disable features not needed for analysis
          logSearchInfo = false
          logToStderr = true
          """
      try? configContent.write(to: configURL, atomically: true, encoding: .utf8)
      
      return (configURL.path, modelPath)
  }

  // MARK: - ONNX Engine Methods

  private func startEngineOnnx(args: [String: Any]?, result: @escaping FlutterResult) {
      #if targetEnvironment(simulator)
      // ONNX may not work well on iOS Simulator
      NSLog("[KataGoONNX] Simulator detected, skipping ONNX engine")
      result(false)
      return
      #endif

      guard let args = args else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
      }

      let boardSize = args["boardSize"] as? Int ?? 19

      if isOnnxInitialized {
          NSLog("[KataGoONNX] Engine already initialized")
          result(true)
          return
      }

      DispatchQueue.global(qos: .userInitiated).async {
          // Prepare resources
          let (configPath, modelBinPath, modelOnnxPath) = self.prepareOnnxResources(boardSize: boardSize)

          guard let config = configPath,
                let modelBin = modelBinPath,
                let modelOnnx = modelOnnxPath else {
              DispatchQueue.main.async {
                  result(FlutterError(code: "RESOURCE_ERROR", message: "Failed to prepare resources", details: nil))
              }
              return
          }

          // Initialize ONNX engine
          let success = KataGoOnnxBridge.initialize(
              withConfig: config,
              modelBin: modelBin,
              modelOnnx: modelOnnx,
              boardSize: Int32(boardSize)
          )

          isOnnxInitialized = success
          DispatchQueue.main.async {
              result(success)
          }
      }
  }

  private func analyzeOnnx(args: [String: Any]?, result: @escaping FlutterResult) {
      guard isOnnxInitialized else {
          result(FlutterError(code: "NOT_INITIALIZED", message: "ONNX engine not initialized", details: nil))
          return
      }

      guard let args = args else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
      }

      let maxVisits = args["maxVisits"] as? Int ?? 500

      // Start progress timer before analysis
      startProgressTimer(maxVisits: maxVisits)

      DispatchQueue.global(qos: .userInitiated).async {
          // Call ONNX bridge (synchronous, blocks until search completes)
          let jsonResult = KataGoOnnxBridge.analyzePosition(args)

          // Stop timer and send final progress
          DispatchQueue.main.async {
              self.stopProgressTimer()

              // Send completion event
              if let sink = self.eventSink {
                  let event: [String: Any] = [
                      "type": "onnx_progress",
                      "currentVisits": maxVisits,
                      "maxVisits": maxVisits,
                      "isComplete": true
                  ]
                  sink(event)
              }

              if let jsonResult = jsonResult {
                  result(jsonResult)
              } else {
                  result(FlutterError(code: "ANALYSIS_FAILED", message: "ONNX analysis failed", details: nil))
              }
          }
      }
  }

  private func cancelAnalysisOnnx(result: @escaping FlutterResult) {
      KataGoOnnxBridge.requestStop()
      stopProgressTimer()
      result(true)
  }

  private func startProgressTimer(maxVisits: Int) {
      stopProgressTimer()  // Cancel any existing timer

      let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
      timer.schedule(deadline: .now() + 0.3, repeating: 0.3)
      timer.setEventHandler { [weak self] in
          let currentVisits = KataGoOnnxBridge.getCurrentVisits()
          let max = KataGoOnnxBridge.getMaxVisits()
          DispatchQueue.main.async {
              guard let sink = self?.eventSink else { return }
              let event: [String: Any] = [
                  "type": "onnx_progress",
                  "currentVisits": currentVisits,
                  "maxVisits": max,
                  "isComplete": false
              ]
              sink(event)
          }
      }
      timer.resume()
      progressTimer = timer
  }

  private func stopProgressTimer() {
      progressTimer?.cancel()
      progressTimer = nil
  }

  private func stopEngineOnnx(result: FlutterResult) {
      if !isOnnxInitialized {
          result(true)
          return
      }

      KataGoOnnxBridge.destroy()
      isOnnxInitialized = false
      result(true)
  }

  private func prepareOnnxResources(boardSize: Int) -> (String?, String?, String?) {
      // 1. Model.bin.gz path
      let modelBinKey = FlutterDartProject.lookupKey(forAsset: "assets/katago/model.bin")
      guard let modelBinPath = Bundle.main.path(forResource: modelBinKey, ofType: nil) else {
          NSLog("[KataGoONNX] Failed to find model.bin")
          return (nil, nil, nil)
      }

      // 2. Board-size-specific ONNX model
      let modelOnnxKey = FlutterDartProject.lookupKey(forAsset: "assets/katago/model_\(boardSize)x\(boardSize).onnx")
      var modelOnnxPath = Bundle.main.path(forResource: modelOnnxKey, ofType: nil)

      if modelOnnxPath == nil {
          NSLog("[KataGoONNX] Failed to find model_\(boardSize)x\(boardSize).onnx")
          // Fallback to generic model
          let fallbackKey = FlutterDartProject.lookupKey(forAsset: "assets/katago/model.onnx")
          if let fallbackPath = Bundle.main.path(forResource: fallbackKey, ofType: nil) {
              modelOnnxPath = fallbackPath
              NSLog("[KataGoONNX] Using fallback model.onnx")
          } else {
              NSLog("[KataGoONNX] Fallback model.onnx also not found")
              return (nil, nil, nil)
          }
      }

      // 3. Config file (create in Documents directory)
      let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let configURL = docDir.appendingPathComponent("analysis_onnx.cfg")

      let configContent = """
          # KataGo Analysis Config for iOS ONNX

          # Limits
          maxVisits = 500
          numSearchThreads = 1

          # Analysis output
          reportAnalysisWinratesAs = BLACK

          # Performance tuning for mobile (single-threaded)
          nnCacheSizePowerOfTwo = 18
          nnMutexPoolSizePowerOfTwo = 14
          numNNServerThreadsPerModel = 1
          nnMaxBatchSize = 1

          # Disable features not needed for analysis
          logSearchInfo = false
          logToStderr = true
          """

      try? configContent.write(to: configURL, atomically: true, encoding: .utf8)

      return (configURL.path, modelBinPath, modelOnnxPath)
  }
}

// Separate extension for StreamHandler?
extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
