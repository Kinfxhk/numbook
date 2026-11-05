import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  func prepareQuit(completion: @escaping (Bool) -> Void) {
    guard let controller = contentViewController as? FlutterViewController else {
      completion(false)
      return
    }
    let channel = FlutterMethodChannel(name: "app.numbook/lifecycle", binaryMessenger: controller.engine.binaryMessenger)
    channel.invokeMethod("prepareQuit", arguments: nil) { result in
      completion((result as? Bool) == true)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
