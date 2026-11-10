import XCTest

final class QuitPolicyTests: XCTestCase {
  func testQuitWithNoWindowTerminatesInsteadOfCancelling() {
    let surface = resolveQuitSurface(listed: false, retained: false, viewAlive: false)
    XCTAssertEqual(surface, .noWindow)
    XCTAssertEqual(quitStep(surface: surface, saveInFlight: false), .terminateNow)
  }

  func testClosedWindowThatIsStillRetainedCanStillSave() {
    let surface = resolveQuitSurface(listed: false, retained: true, viewAlive: true)
    XCTAssertEqual(surface, .ready)
    XCTAssertEqual(quitStep(surface: surface, saveInFlight: false), .persistThenReply)
  }

  func testQuitWithDeadViewTerminatesInsteadOfCancelling() {
    let listed = resolveQuitSurface(listed: true, retained: true, viewAlive: false)
    let retainedOnly = resolveQuitSurface(listed: false, retained: true, viewAlive: false)
    XCTAssertEqual(listed, .viewGone)
    XCTAssertEqual(retainedOnly, .viewGone)
    XCTAssertEqual(quitStep(surface: listed, saveInFlight: false), .terminateNow)
    XCTAssertEqual(quitStep(surface: retainedOnly, saveInFlight: false), .terminateNow)
  }

  func testQuitWithLiveViewPersistsFirst() {
    let surface = resolveQuitSurface(listed: true, retained: false, viewAlive: true)
    XCTAssertEqual(surface, .ready)
    XCTAssertEqual(quitStep(surface: surface, saveInFlight: false), .persistThenReply)
  }

  func testSecondQuitWhileSavingDoesNotReplyAgain() {
    XCTAssertEqual(quitStep(surface: .ready, saveInFlight: true), .keepWaiting)
    XCTAssertEqual(quitStep(surface: .noWindow, saveInFlight: true), .keepWaiting)
    XCTAssertEqual(quitStep(surface: .viewGone, saveInFlight: true), .keepWaiting)
  }

  func testQuitAfterTheWindowAlreadySavedDoesNotAskTheEngineAgain() {
    XCTAssertEqual(
      quitStep(surface: .ready, saveInFlight: false, alreadySavedForClose: true),
      .terminateNow
    )
    XCTAssertEqual(
      quitStep(surface: .ready, saveInFlight: true, alreadySavedForClose: true),
      .keepWaiting
    )
  }

  func testFailedSaveWithUsableWindowCancelsQuit() {
    XCTAssertEqual(saveFollowUp(saved: false, canKeepWorking: true), .cancelAndAlert)
  }

  func testFailedSaveAfterTheWindowIsGoneDoesNotTrapTheProcess() {
    XCTAssertEqual(saveFollowUp(saved: false, canKeepWorking: false), .proceed)
  }

  func testSuccessfulSaveProceeds() {
    XCTAssertEqual(saveFollowUp(saved: true, canKeepWorking: true), .proceed)
    XCTAssertEqual(saveFollowUp(saved: true, canKeepWorking: false), .proceed)
  }

  func testClosingLastWindowPersistsWhileTheViewIsAlive() {
    XCTAssertEqual(
      closeStep(flutterViewAlive: true, closeApproved: false, saveInFlight: false),
      .persistThenClose
    )
  }

  func testCloseAfterTheSaveWasApprovedDoesNotAskAgain() {
    XCTAssertEqual(
      closeStep(flutterViewAlive: true, closeApproved: true, saveInFlight: false),
      .closeNow
    )
  }

  func testCloseWithNoViewClosesImmediately() {
    XCTAssertEqual(
      closeStep(flutterViewAlive: false, closeApproved: false, saveInFlight: false),
      .closeNow
    )
  }

  func testDuplicateCloseWhileSavingIsIgnored() {
    XCTAssertEqual(
      closeStep(flutterViewAlive: true, closeApproved: false, saveInFlight: true),
      .ignoreDuplicate
    )
  }
}
