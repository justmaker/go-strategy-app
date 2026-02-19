import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    print("[macOS AppDelegate] application:open:urls called with \(urls.count) URL(s)")
    for url in urls {
      print("[macOS AppDelegate] URL: \(url)")
    }
    super.application(application, open: urls)
  }
}
