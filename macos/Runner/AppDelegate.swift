import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var quitPending = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitPending { return .terminateLater }
    guard let window = sender.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow else {
      return .terminateCancel
    }
    quitPending = true
    window.prepareQuit { [weak self] saved in
      DispatchQueue.main.async {
        self?.quitPending = false
        sender.reply(toApplicationShouldTerminate: saved)
        if !saved {
          let alert = NSAlert()
          alert.messageText = "Numbook could not save your changes"
          alert.informativeText = "Quit was cancelled to protect your notes. Check available disk space and try saving again."
          alert.addButton(withTitle: "Keep working")
          alert.beginSheetModal(for: window)
        }
      }
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
