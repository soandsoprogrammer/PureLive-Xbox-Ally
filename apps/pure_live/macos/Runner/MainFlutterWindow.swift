import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMethodChannel(
      name: "pure_live/secret_cipher", binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler(SecretCipher.shared.handle)
    // A downloaded update selected in Finder (A18.2 c10, "在访达中显示").
    FlutterMethodChannel(
      name: "pure_live/finder", binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "reveal",
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let url = URL(fileURLWithPath: path)
      guard FileManager.default.fileExists(atPath: url.path) else {
        result(false)
        return
      }
      NSWorkspace.shared.activateFileViewerSelecting([url])
      result(true)
    }

    super.awakeFromNib()
  }
}
