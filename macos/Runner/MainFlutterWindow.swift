import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var closeApproved = false
  private var saveOnCloseInFlight = false

  var hasFlutterView: Bool {
    contentViewController is FlutterViewController
  }

  /// The alert needs a visible window. A closed window cannot host it, and
  /// cancelling quit at that point leaves the process with no UI.
  var canKeepWorking: Bool {
    isVisible && hasFlutterView
  }

  func approveCloseForTermination() {
    closeApproved = true
  }

  /// True after a successful save that is about to order the window out.
  var didPersistBeforeClose: Bool {
    closeApproved
  }

  func prepareQuit(completion: @escaping (Bool) -> Void) {
    guard let controller = contentViewController as? FlutterViewController else {
      completion(false)
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.numbook/lifecycle",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("prepareQuit", arguments: nil) { result in
      completion((result as? Bool) == true)
    }
  }

  /// Closing the last window asks the app to terminate after the window has
  /// already left `NSApplication.windows`. Persist first, while the engine
  /// is still here. A failed save keeps the window open.
  override func close() {
    switch closeStep(
      flutterViewAlive: hasFlutterView,
      closeApproved: closeApproved,
      saveInFlight: saveOnCloseInFlight
    ) {
    case .closeNow:
      super.close()
    case .ignoreDuplicate:
      return
    case .persistThenClose:
      saveOnCloseInFlight = true
      prepareQuit { [weak self] saved in
        DispatchQueue.main.async {
          guard let self = self else { return }
          self.saveOnCloseInFlight = false
          switch saveFollowUp(saved: saved, canKeepWorking: self.canKeepWorking) {
          case .proceed:
            self.closeApproved = true
            self.close()
          case .cancelAndAlert:
            presentQuitSaveFailedAlert(on: self)
          }
        }
      }
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    (NSApp.delegate as? AppDelegate)?.noteMainWindow(self)

    super.awakeFromNib()
  }
}
