import XCTest

/// Black-box regressions against the shipped UI. Every case launches its own
/// in-memory registry; no test-only authentication or lifecycle shortcuts exist.
@MainActor
final class SessionUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 10))
    XCTAssertEqual(element("selected-session-status").label, "Not signed in")
    let initial = inspectOwnership()
    XCTAssertEqual(initial.environment, "Production")
    XCTAssertEqual(initial.value, "0")
    XCTAssertNil(initial.authenticatedServices)
    XCTAssertEqual(retainedSessionIDs(), [initial.session])
  }

  override func tearDownWithError() throws {
    if let testRun, testRun.totalFailureCount > 0 {
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.lifetime = .keepAlways
      add(screenshot)
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "Accessibility hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
    }
    app.terminate()
    app = nil
  }

  func testLoginPreservesOwnershipAndProfileDraft() {
    let before = inspectOwnership()
    incrementValue()
    startSignIn(as: "Jordan")
    tap(app.buttons["complete-sign-in-button"])
    let draft = app.textFields["profile-display-name"]
    XCTAssertTrue(draft.waitForExistence(timeout: 5))
    XCTAssertEqual(draft.value as? String, "Jordan")
    draft.tap()
    draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Jordan Edited")
    openLab()
    closeLab()
    XCTAssertEqual(draft.value as? String, "Jordan Edited")
    completeSetup()
    tap(app.tabBars.buttons["Account"])
    XCTAssertEqual(element("account-name").label, "Jordan")
    let after = inspectOwnership()
    assertSameOwners(before, after)
    XCTAssertEqual(after.value, "1")
    XCTAssertNotNil(after.authenticatedServices)

    tap(app.buttons["logout-replace-button"])
    XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
    let replacement = inspectOwnership()
    assertFreshReplacement(of: after, replacement)
    startSignIn(as: "Taylor")
    tap(app.buttons["complete-sign-in-button"])
    XCTAssertTrue(draft.waitForExistence(timeout: 5))
    XCTAssertEqual(draft.value as? String, "Taylor")
    XCTAssertEqual(selectedID, replacement.session)
  }

  func testRetainedSessionsKeepIndependentAccountsAndNavigation() {
    signIn(as: "Jordan")
    incrementValue()
    let production = inspectOwnership()
    tap(app.tabBars.buttons["Account"])
    tap(app.buttons["open-preferences-button"])
    enableCompactAppearance()

    let stagingID = createSession(environment: "Staging")
    signIn(as: "Taylor")
    incrementValue(times: 2)
    let staging = inspectOwnership()
    XCTAssertEqual(staging.session, stagingID)
    XCTAssertEqual(staging.environment, "Staging")
    XCTAssertEqual(staging.value, "2")
    XCTAssertNotEqual(production.services, staging.services)
    XCTAssertNotEqual(production.storage, staging.storage)
    XCTAssertNotEqual(production.authenticatedServices, staging.authenticatedServices)
    XCTAssertEqual(Set(retainedSessionIDs()), Set([production.session, staging.session]))

    selectSession(production.session)
    XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.switches["Compact Appearance"].value as? String, "1")
    XCTAssertEqual(element("selected-session-status").label, "Signed in as Jordan")
    let restored = inspectOwnership()
    assertSameOwners(production, restored)
    XCTAssertEqual(restored.value, "1")
    XCTAssertEqual(restored.authenticatedServices, production.authenticatedServices)

    selectSession(staging.session)
    tap(app.tabBars.buttons["Account"])
    XCTAssertEqual(element("account-name").label, "Taylor")
    XCTAssertEqual(inspectOwnership().value, "2")
  }

  func testLogoutDrainsLateWriteWithoutStealingSelection() {
    signIn()
    incrementValue()
    let old = inspectOwnership()
    let stagingID = createSession(environment: "Staging")
    selectSession(old.session)

    openLab()
    reveal(app.buttons["start-background-write-button"])
    tap(app.buttons["start-background-write-button"])
    tap(app.buttons["lab-logout-replace-button"])
    XCTAssertFalse(app.buttons["increment-session-value-button"].isEnabled)
    XCTAssertFalse(app.buttons["dispose-session-button"].isEnabled)
    closeLab()
    XCTAssertTrue(app.buttons["deliver-closing-callbacks-button"].waitForExistence(timeout: 5))
    XCTAssertEqual(Set(retainedSessionIDs()), Set([old.session, stagingID]))

    selectSession(stagingID)
    openLab()
    tap(app.segmentedControls["session-lab-pages"].buttons["Callbacks"])
    tap(app.buttons["deliver-all-callbacks-button"])
    tap(app.segmentedControls["session-lab-pages"].buttons["Events"])
    let disposed = element("disposed-session-\(old.session)")
    XCTAssertTrue(disposed.waitForExistence(timeout: 5))
    XCTAssertEqual(disposed.value as? String, "1")
    let rejection = app.descendants(matching: .any).matching(NSPredicate(
      format: "identifier == %@ AND label CONTAINS %@",
      "session-event-\(old.session)", "Rejected late callback: Background write"
    )).firstMatch
    reveal(rejection)
    XCTAssertTrue(rejection.exists)
    closeLab()
    XCTAssertEqual(selectedID, stagingID)
    XCTAssertEqual(inspectOwnership().value, "0")

    let ids = retainedSessionIDs()
    XCTAssertEqual(ids.count, 2)
    XCTAssertFalse(ids.contains(old.session))
    let replacementID = ids.first { $0 != stagingID }!
    selectSession(replacementID)
    XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
    assertFreshReplacement(of: old, inspectOwnership())
  }

  func testDisposalDuringAuthenticationRejectsLateSuccess() {
    let oldID = selectedID
    startSignIn()
    tap(app.buttons["dispose-during-sign-in-button"])
    XCTAssertTrue(app.buttons["deliver-closing-callbacks-button"].waitForExistence(timeout: 5))
    XCTAssertEqual(retainedSessionIDs(), [oldID])
    tap(app.buttons["deliver-closing-callbacks-button"])
    XCTAssertTrue(app.staticTexts["No active Session selected"].waitForExistence(timeout: 5))
    XCTAssertTrue(retainedSessionIDs().isEmpty)
    openLab()
    tap(app.segmentedControls["session-lab-pages"].buttons["Events"])
    let rejection = app.descendants(matching: .any).matching(NSPredicate(
      format: "identifier == %@ AND label CONTAINS %@",
      "session-event-\(oldID)", "Rejected late callback: Sign in"
    )).firstMatch
    reveal(rejection)
    XCTAssertTrue(rejection.exists)
    closeLab()
    XCTAssertNotEqual(createSession(environment: "Production"), oldID)
    XCTAssertNil(inspectOwnership().authenticatedServices)
  }

  func testDeferredDeepLinkReplaysOnlyInItsSession() {
    let firstID = selectedID
    XCUIDevice.shared.system.open(URL(string: "uicontext-demo://account/preferences")!)
    XCTAssertEqual(selectedID, firstID)
    XCTAssertTrue(app.staticTexts["Queued route: Open Preferences"].waitForExistence(timeout: 5))
    let otherID = createSession(environment: "Staging")
    signIn(as: "Jordan")
    XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
    tap(app.tabBars.buttons["Account"])
    XCTAssertFalse(app.navigationBars["Preferences"].exists)
    selectSession(firstID)
    signIn()
    XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 5))
    XCTAssertEqual(selectedID, firstID)
    selectSession(otherID)
    XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
  }

  func testRouteLabAndRestrictionPreserveTabs() {
    signIn()
    for tab in ["Home", "Activity", "Messages", "Account"] {
      tap(app.tabBars.buttons[tab])
      XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
    }
    route("Open Mentions")
    XCTAssertEqual(app.segmentedControls["activity-filter"].buttons["Mentions"].isSelected, true)
    route("Open Preferences")
    enableCompactAppearance()
    route("Enter Restricted Mode")
    XCTAssertTrue(app.staticTexts["Access is paused"].waitForExistence(timeout: 5))
    tap(app.buttons["Restore Access"])
    XCTAssertTrue(app.navigationBars["Preferences"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.switches["Compact Appearance"].value as? String, "1")
    let sessionID = selectedID
    XCUIDevice.shared.system.open(URL(string: "uimodel-demo://activity/mentions")!)
    XCTAssertEqual(selectedID, sessionID)
    XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.segmentedControls["activity-filter"].buttons["Mentions"].isSelected)
  }

  func testUnauthenticatedDisposalLeavesNoSessions() {
    let oldID = selectedID
    openLab()
    reveal(app.buttons["dispose-session-button"])
    tap(app.buttons["dispose-session-button"])
    closeLab()
    XCTAssertTrue(app.staticTexts["No active Session selected"].waitForExistence(timeout: 5))
    XCTAssertTrue(retainedSessionIDs().isEmpty)
    XCTAssertNotEqual(createSession(environment: "Staging"), oldID)
    let new = inspectOwnership()
    XCTAssertEqual(new.environment, "Staging")
    XCTAssertEqual(new.value, "0")
    XCTAssertNil(new.authenticatedServices)
  }

  func testAuthenticationFailureAllowsRetryInSameSession() {
    let before = inspectOwnership()
    startSignIn(as: "Jordan")
    tap(app.buttons["Fail Sign In"])
    XCTAssertTrue(app.staticTexts["Mock authentication failed. The same Session can retry."].waitForExistence(timeout: 5))
    assertSameOwners(before, inspectOwnership())
    signIn(as: "Jordan")
    tap(app.tabBars.buttons["Account"])
    XCTAssertEqual(element("account-name").label, "Jordan")
    assertSameOwners(before, inspectOwnership())
  }

  // MARK: - UI-only helpers

  /// Values sampled from the inspector for one comparison, not retained app state.
  private struct Ownership {
    let session: String
    let services: String
    let storage: String
    let authenticatedServices: String?
    let environment: String
    let value: String
  }

  private var selectedID: String {
    let identity = element("selected-session-identity")
    XCTAssertTrue(identity.exists || identity.waitForExistence(timeout: 5))
    return identity.value as! String
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(element.exists || element.waitForExistence(timeout: 5), "Missing \(element)", file: file, line: line)
    element.tap()
  }

  /// Bounded scrolling rather than coordinates for individual controls or sleeps.
  private func reveal(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    let list = app.collectionViews.firstMatch
    let scrollView = list.exists ? list : app.scrollViews.firstMatch
    for _ in 0..<10 {
      if target.exists && target.isHittable { return }
      scrollView.swipeUp()
    }
    XCTFail("Cannot reveal \(target)", file: file, line: line)
  }

  private func openLab() {
    tap(app.buttons["session-lab-button"])
    let navigationBar = app.navigationBars["Session Lab"]
    XCTAssertTrue(navigationBar.exists || navigationBar.waitForExistence(timeout: 5))
  }

  private func closeLab() {
    tap(app.navigationBars["Session Lab"].buttons["Done"])
    XCTAssertTrue(app.navigationBars["Session Lab"].waitForNonExistence(timeout: 5))
  }

  private func inspectOwnership() -> Ownership {
    openLab()
    let value = element("session-store-value").value as! String
    let environment = element("session-environment").value as! String
    tap(app.buttons["Ownership details"])
    let session = element("ownership-session-id").label
    let services = element("ownership-services-id").label
    let storage = element("ownership-storage-id").label
    let authenticated = element("ownership-authenticated-id")
    let authenticatedID = authenticated.exists ? authenticated.label : nil
    for id in [session, services, storage] { XCTAssertNotNil(UUID(uuidString: id)) }
    closeLab()
    return Ownership(
      session: session, services: services, storage: storage,
      authenticatedServices: authenticatedID, environment: environment, value: value
    )
  }

  private func incrementValue(times: Int = 1) {
    openLab()
    let increment = app.buttons["increment-session-value-button"]
    reveal(increment)
    for _ in 0..<times { tap(increment) }
    closeLab()
  }

  private func createSession(environment: String) -> String {
    openLab()
    let picker = app.segmentedControls["new-session-environment"]
    reveal(picker)
    tap(picker.buttons[environment])
    reveal(app.buttons["create-session-button"])
    tap(app.buttons["create-session-button"])
    closeLab()
    XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
    return selectedID
  }

  private func selectSession(_ id: String) {
    openLab()
    let row = app.buttons["select-session-\(id)"]
    reveal(row)
    tap(row)
    closeLab()
    XCTAssertEqual(selectedID, id)
  }

  private func retainedSessionIDs() -> [String] {
    openLab()
    reveal(app.buttons["create-session-button"])
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select-session-"))
    let ids = rows.allElementsBoundByIndex.map { String($0.identifier.dropFirst("select-session-".count)) }
    closeLab()
    return ids
  }

  private func startSignIn(as account: String = "Taylor") {
    tap(app.segmentedControls["mock-account-picker"].buttons[account])
    tap(app.buttons["sign-in-button"])
    XCTAssertTrue(app.buttons["complete-sign-in-button"].waitForExistence(timeout: 5))
  }

  private func signIn(as account: String = "Taylor") {
    startSignIn(as: account)
    tap(app.buttons["complete-sign-in-button"])
    completeSetup()
  }

  private func completeSetup() {
    tap(app.buttons["setup-continue-button"])
    tap(app.buttons["finish-setup-button"])
    tap(app.buttons["enter-app-button"])
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
  }

  private func route(_ title: String) {
    tap(app.buttons["route-lab-button"])
    let button = app.buttons[title]
    reveal(button)
    tap(button)
  }

  private func enableCompactAppearance() {
    let toggle = app.switches["Compact Appearance"]
    XCTAssertEqual(toggle.value as? String, "0")
    // SwiftUI can expose both the labeled row and its actual switch.
    let control = toggle.switches.firstMatch
    tap(control.exists ? control : toggle)
    XCTAssertEqual(toggle.value as? String, "1")
  }

  private func assertSameOwners(_ first: Ownership, _ second: Ownership, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(first.session, second.session, file: file, line: line)
    XCTAssertEqual(first.services, second.services, file: file, line: line)
    XCTAssertEqual(first.storage, second.storage, file: file, line: line)
    XCTAssertEqual(first.environment, second.environment, file: file, line: line)
  }

  private func assertFreshReplacement(of old: Ownership, _ new: Ownership, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNotEqual(old.session, new.session, file: file, line: line)
    XCTAssertNotEqual(old.services, new.services, file: file, line: line)
    XCTAssertNotEqual(old.storage, new.storage, file: file, line: line)
    XCTAssertEqual(old.environment, new.environment, file: file, line: line)
    XCTAssertEqual(new.value, "0", file: file, line: line)
    XCTAssertNil(new.authenticatedServices, file: file, line: line)
  }
}
