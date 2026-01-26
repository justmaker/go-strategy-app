import Flutter
import UIKit
// import KataGoMobile // If using module, or bridging header if not. Using module via Pod.

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  // Flag to track engine state
  var isRunning = false
  
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
  
  private func startEngine(result: FlutterResult) {
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
      let assetKeyModel = FlutterDartProject.lookupKey(forAsset: "assets/katago/model.bin.gz")
      let modelPath = Bundle.main.path(forResource: assetKeyModel, ofType: nil)
      
      // Config: create file in Docs
      let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let configURL = docDir.appendingPathComponent("analysis.cfg")
      // Write default config
      let configContent = "maxVisits = 50\nnumSearchThreads = 1\n"
      try? configContent.write(to: configURL, atomically: true, encoding: .utf8)
      
      return (configURL.path, modelPath)
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
