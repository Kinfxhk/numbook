import Cocoa
import FlutterMacOS

func presentQuitSaveFailedAlert(on window: NSWindow) {
  let alert = NSAlert()
  alert.messageText = "Numbook could not save your changes"
  alert.informativeText = "Quit was cancelled to protect your notes. Check available disk space and try saving again."
  alert.addButton(withTitle: "Keep working")
  alert.beginSheetModal(for: window)
}

@main
class AppDelegate: FlutterAppDelegate {
  private var quitPending = false

  /// Survives `close()` because the nib sets `releasedWhenClosed = NO`.
  /// `NSApplication.windows` drops the window as soon as it orders out.
  weak var retainedFlutterWindow: MainFlutterWindow?

  func noteMainWindow(_ window: MainFlutterWindow) {
    retainedFlutterWindow = window
  }

  private func flutterWindow(in app: NSApplication) -> MainFlutterWindow? {
    if let listed = app.windows.compactMap({ $0 as? MainFlutterWindow }).first {
      return listed
    }
    return retainedFlutterWindow
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let listed = sender.windows.contains { $0 is MainFlutterWindow }
    let window = flutterWindow(in: sender)
    let surface = resolveQuitSurface(
      listed: listed,
      retained: retainedFlutterWindow != nil,
      viewAlive: window?.hasFlutterView ?? false
    )
    switch quitStep(
      surface: surface,
      saveInFlight: quitPending,
      alreadySavedForClose: window?.didPersistBeforeClose ?? false
    ) {
    case .keepWaiting:
      return .terminateLater
    case .terminateNow:
      return .terminateNow
    case .persistThenReply:
      guard let window else {
        return .terminateNow
      }
      quitPending = true
      window.prepareQuit { [weak self] saved in
        DispatchQueue.main.async {
          guard let self = self else {
            sender.reply(toApplicationShouldTerminate: true)
            return
          }
          switch saveFollowUp(saved: saved, canKeepWorking: window.canKeepWorking) {
          case .proceed:
            window.approveCloseForTermination()
            sender.reply(toApplicationShouldTerminate: true)
          case .cancelAndAlert:
            sender.reply(toApplicationShouldTerminate: false)
            presentQuitSaveFailedAlert(on: window)
          }
          self.quitPending = false
        }
      }
      return .terminateLater
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
