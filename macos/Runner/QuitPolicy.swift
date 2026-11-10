/// Where the document engine is, from the application's point of view.
enum QuitSurface {
  /// No MainFlutterWindow is listed, and none is still retained.
  case noWindow
  /// A window object exists, but its Flutter view is already gone.
  case viewGone
  /// A live Flutter view can still persist the library.
  case ready
}

enum QuitStep {
  /// A save is already in flight. Keep termination deferred and do not reply again.
  case keepWaiting
  /// Nothing left can persist, or the close path already did. Cancelling traps the process.
  case terminateNow
  /// Ask the Flutter view to persist, then reply with that result.
  case persistThenReply
}

enum CloseStep {
  case closeNow
  /// close() was called again while the save for this close is running.
  case ignoreDuplicate
  /// Persist while the view is alive, then close only if that succeeds.
  case persistThenClose
}

enum SaveFollowUp {
  case proceed
  case cancelAndAlert
}

/// `listed` is membership in `NSApplication.windows`. A window with
/// `releasedWhenClosed = NO` leaves that array when it closes and is easy to
/// mistake for "already destroyed".
func resolveQuitSurface(listed: Bool, retained: Bool, viewAlive: Bool) -> QuitSurface {
  if !listed && !retained {
    return .noWindow
  }
  if !viewAlive {
    return .viewGone
  }
  return .ready
}

func quitStep(
  surface: QuitSurface,
  saveInFlight: Bool,
  alreadySavedForClose: Bool = false
) -> QuitStep {
  if saveInFlight {
    return .keepWaiting
  }
  // The window-close path persists, then orders the window out, and that
  // close is what starts tearing the engine down. Asking again from
  // applicationShouldTerminate can wait forever for a reply that never comes.
  if alreadySavedForClose {
    return .terminateNow
  }
  switch surface {
  case .ready:
    return .persistThenReply
  case .noWindow, .viewGone:
    return .terminateNow
  }
}

func closeStep(flutterViewAlive: Bool, closeApproved: Bool, saveInFlight: Bool) -> CloseStep {
  if closeApproved || !flutterViewAlive {
    return .closeNow
  }
  if saveInFlight {
    return .ignoreDuplicate
  }
  return .persistThenClose
}

/// A failed save cancels quit only while the user still has a window to keep
/// working in. After the view is gone, cancelling can only be undone by force-quit.
func saveFollowUp(saved: Bool, canKeepWorking: Bool) -> SaveFollowUp {
  if saved || !canKeepWorking {
    return .proceed
  }
  return .cancelAndAlert
}
