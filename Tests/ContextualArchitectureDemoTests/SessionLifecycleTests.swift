import Foundation
import Testing
@testable import ContextualArchitectureDemo

@Suite @MainActor
struct SessionLifecycleTests {
  @Test func containersExistBeforeLoginAndHaveFixedStorageBindings() {
    let app = AppUIContext(createInitialSession: false)
    let first = app.createSession(environment: .production)
    let second = app.createSession(environment: .production)
    let staging = app.createSession(environment: .staging)

    #expect(app.sessions.count == 3)
    #expect(first.id != second.id && second.id != staging.id)
    #expect(first.services !== second.services)
    #expect(first.services.store !== second.services.store)
    #expect(first.authenticatedServices == nil)
    #expect(first.uiContext.sessionID == first.id)
    #expect(first.services.store.sessionID == first.id)
    #expect(first.services.store.environment == .production)
    #expect(first.services.store.namespace.contains(first.id.uuidString))
    #expect(staging.services.store.namespace.contains("Environments/staging/"))

    first.services.increment()
    #expect(first.services.store.value == 1)
    #expect(second.services.store.value == 0)
    #expect(staging.services.store.value == 0)
    #expect(first.environment == .production)
  }

  @Test func authenticationCreatesChildrenWithoutReplacingContainer() async throws {
    let app = AppUIContext()
    let session = try #require(app.selectedSession)
    let id = session.id
    let services = session.services
    let store = services.store
    session.services.increment()
    session.signIn(as: .jordan)
    #expect(session.authenticatedServices == nil)
    #expect(session.services.pendingCount == 1)
    session.signIn(as: .taylor)
    #expect(app.transport.requests.count == 1)

    app.transport.resolveAll()
    await services.waitForCurrentWork()
    #expect(session.id == id)
    #expect(session.services === services)
    #expect(session.services.store === store)
    #expect(store.value == 1)
    #expect(session.authenticatedServices?.account == .jordan)
    guard case .signedIn(let child) = session.uiContext.authentication else {
      Issue.record("Expected authenticated child")
      return
    }
    #expect(child.account == .jordan)
  }

  @Test func failedAuthenticationCanRetryInsideSameContainer() async throws {
    let app = AppUIContext()
    let session = try #require(app.selectedSession)
    session.signIn(as: .taylor)
    let failedRequest = try #require(session.authenticationRequestID)
    app.transport.resolve(failedRequest, succeeded: false)
    await session.services.waitForCurrentWork()
    #expect(session.isActive && !session.isAuthenticated)
    guard case .signedOut(let signIn) = session.uiContext.authentication else {
      Issue.record("Expected signed-out UI after failure")
      return
    }
    #expect(signIn.errorMessage != nil)
    session.signIn(as: .jordan)
    let newRequest = try #require(session.authenticationRequestID)
    #expect(newRequest != failedRequest)
    app.transport.resolve(failedRequest)
    #expect(session.authenticatedServices == nil)
    app.transport.resolve(newRequest)
    await session.services.waitForCurrentWork()
    #expect(session.authenticatedServices?.account == .jordan)
    #expect(app.sessions.count == 1)
  }

  @Test func selectionRetainsOtherSessionsNavigationAndWork() async throws {
    let app = AppUIContext()
    let first = try #require(app.selectedSession)
    await authenticate(first, in: app)
    makeReady(first)
    first.uiContext.send(.openPreferences)
    let tabs = try #require(first.uiContext.mainForTesting?.tabs)
    guard case .preferences(let preferences) = tabs.account.path.first else {
      Issue.record("Expected preferences path")
      return
    }
    preferences.notificationsEnabled = false
    first.services.startBackgroundWrite()

    let second = app.createSession(environment: .staging)
    await authenticate(second, in: app, as: .jordan)
    app.transport.resolveAll()
    await first.services.waitForCurrentWork()
    #expect(first.isAuthenticated && second.isAuthenticated)
    #expect(first.services.store.value == 1)
    #expect(second.services.store.value == 0)
    app.select(first.id)
    #expect(app.selectedSession === first)
    #expect(first.uiContext.mainForTesting?.tabs === tabs)
    #expect(tabs.selectedTab == .account)
    #expect(preferences.notificationsEnabled == false)
    #expect(!second.services.store.isClosed)
  }

  @Test func unauthenticatedDisposalClosesWritesAndRemovesOnlyItsContainer() async throws {
    let app = AppUIContext()
    let first = try #require(app.selectedSession)
    first.services.increment()
    let second = app.createSession(environment: .staging, select: false)
    let ending = try #require(app.endSession(first.id))
    #expect(!first.isActive)
    #expect(!first.services.store.increment())
    #expect(first.services.request("Must reject") { _ in Issue.record("Admitted retired work") } == nil)
    _ = await ending.value
    #expect(first.services.store.isClosed)
    #expect(first.services.store.value == 1)
    #expect(app.sessions.count == 1)
    #expect(app.selectedSession === second)
    #expect(app.disposedSessions.first?.replacementID == nil)
  }

  @Test func disposalDuringAuthenticationWaitsForAndRejectsLateSuccess() async throws {
    let app = AppUIContext()
    let session = try #require(app.selectedSession)
    session.uiContext.send(.openPreferences)
    session.signIn()
    let request = try #require(session.authenticationRequestID)
    let ending = try #require(app.endSession(session.id))
    #expect(session.uiContext.pendingIntent == nil)
    #expect(!session.uiContext.acceptsInput)
    #expect(session.services.store.isRetired)
    #expect(!session.services.store.isClosed)
    #expect(app.sessions.count == 1)
    #expect(app.disposedSessions.isEmpty)
    session.signIn()
    #expect(app.transport.requests.count == 1)

    app.transport.resolve(request)
    _ = await ending.value
    #expect(session.authenticatedServices == nil)
    #expect(session.services.pendingCount == 0)
    #expect(session.services.store.isClosed)
    #expect(app.sessions.isEmpty && app.selectedSession == nil)
    #expect(app.log.entries.contains { $0.message.hasPrefix("Rejected late callback") })
    guard case .closed = session.uiContext.authentication else {
      Issue.record("Expected closed Session UI")
      return
    }
  }

  @Test func logoutDrainsOldWorkBeforeCreatingFreshSameEnvironmentSession() async throws {
    let app = AppUIContext(createInitialSession: false)
    let old = app.createSession(environment: .staging)
    await authenticate(old, in: app)
    old.services.increment()
    old.uiContext.send(.openPreferences)
    old.services.startBackgroundWrite()
    let oldRequest = try #require(app.transport.requests.first)
    let ending = try #require(app.endSession(old.id, replacing: true))
    #expect(app.sessions.count == 1)
    #expect(app.selectedSession === old)
    #expect(old.uiContext.pendingIntent == nil)
    #expect(!old.services.store.isClosed)

    app.transport.resolve(oldRequest.id)
    let replacement = try #require(await ending.value)
    #expect(old.services.store.isClosed)
    #expect(old.services.store.value == 1)
    #expect(old.authenticatedServices == nil)
    #expect(replacement.id != old.id)
    #expect(replacement.environment == old.environment)
    #expect(replacement.services !== old.services)
    #expect(replacement.services.store !== old.services.store)
    #expect(replacement.services.store.namespace != old.services.store.namespace)
    #expect(!replacement.isAuthenticated && replacement.isActive)
    #expect(replacement.uiContext.pendingIntent == nil)
    #expect(app.selectedSession === replacement)

    replacement.services.increment()
    oldRequest.resolve(succeeded: true)
    old.services.increment()
    #expect(!old.services.store.increment())
    #expect(replacement.services.store.value == 1)
    #expect(old.services.store.value == 1)

    let messages = app.log.entries.map(\.message)
    let rejected = try #require(messages.firstIndex { $0.hasPrefix("Rejected late callback") })
    let closed = try #require(messages.firstIndex(of: "Work drained; store closed"))
    let disposed = try #require(messages.firstIndex(of: "Session disposed"))
    let recreated = try #require(messages.lastIndex(of: "Created Staging Session before login"))
    #expect(rejected < closed && closed < disposed && disposed < recreated)
  }

  @Test func repeatedLogoutJoinsOneReplacementAndConflictingPolicyIsRejected() async throws {
    let app = AppUIContext()
    let old = try #require(app.selectedSession)
    await authenticate(old, in: app)
    let first = try #require(app.endSession(old.id, replacing: true))
    let duplicate = try #require(app.endSession(old.id, replacing: true))
    #expect(app.endSession(old.id) == nil)
    let replacement = await first.value
    let duplicateResult = await duplicate.value
    #expect(replacement === duplicateResult)
    #expect(app.sessions.count == 1 && app.disposedSessions.count == 1)
    #expect(app.endSession(old.id, replacing: true) == nil)
  }

  @Test func selectionDuringClosingIsNotOverwrittenByReplacement() async throws {
    let app = AppUIContext()
    let old = try #require(app.selectedSession)
    old.services.startBackgroundWrite()
    let ending = try #require(app.endSession(old.id, replacing: true))
    let other = app.createSession(environment: .staging)
    app.select(old.id)
    #expect(app.selectedSession === other)
    app.transport.resolveAll()
    let replacement = try #require(await ending.value)
    #expect(app.selectedSession === other)
    #expect(app.sessions.contains { $0 === replacement })
    #expect(app.sessions.count == 2)
  }

  @Test func sameAccountReloginGetsFreshAuthenticatedChildrenAndRoutes() async throws {
    let app = AppUIContext()
    let old = try #require(app.selectedSession)
    await authenticate(old, in: app)
    let childID = old.authenticatedServices?.id
    old.uiContext.send(.openPreferences)
    let ending = try #require(app.endSession(old.id, replacing: true))
    let new = try #require(await ending.value)
    await authenticate(new, in: app)
    makeReady(new)
    #expect(new.authenticatedServices?.account == .taylor)
    #expect(new.authenticatedServices?.id != childID)
    #expect(new.uiContext.mainForTesting?.tabs.account.path.isEmpty == true)
  }

  @Test func deferredRoutesBelongOnlyToTheirDestinationSession() async throws {
    let app = AppUIContext()
    let first = try #require(app.selectedSession)
    #expect(app.handle(url: URL(string: "uicontext-demo://account/preferences")!))
    let second = app.createSession(environment: .production)
    await authenticate(second, in: app)
    makeReady(second)
    #expect(second.uiContext.mainForTesting?.tabs.account.path.isEmpty == true)
    #expect(first.uiContext.pendingIntent == .openPreferences)
    await authenticate(first, in: app)
    makeReady(first)
    #expect(first.uiContext.mainForTesting?.tabs.selectedTab == .account)
    #expect(first.uiContext.mainForTesting?.tabs.account.path.count == 1)
    #expect(first.uiContext.pendingIntent == nil)
    #expect(app.selectedSession === second)
  }

  @Test func targetedURLsNeverFallBackToAnotherSession() async throws {
    let app = AppUIContext()
    let first = try #require(app.selectedSession)
    let second = app.createSession(environment: .staging)
    let targeted = URL(string: "uimodel-demo://account/preferences?session=\(first.id)")!
    #expect(app.handle(url: targeted))
    #expect(first.uiContext.pendingIntent == .openPreferences)
    #expect(second.uiContext.pendingIntent == nil)
    #expect(!second.uiContext.handle(url: targeted))
    #expect(!app.handle(url: URL(string: "uimodel-demo://home?session=invalid")!))
    #expect(!app.handle(url: URL(string: "uimodel-demo://home?session=\(UUID())")!))
    #expect(!app.handle(url: URL(string: "uimodel-demo://home?session=\(first.id)&session=\(second.id)")!))
    let ending = try #require(app.endSession(first.id))
    #expect(!app.handle(url: targeted))
    _ = await ending.value
    #expect(!app.handle(url: targeted))
    #expect(second.uiContext.pendingIntent == nil)
  }

  @Test func latestPendingIntentWinsAndRestrictionsRetainTabs() async throws {
    let app = AppUIContext()
    let session = try #require(app.selectedSession)
    session.uiContext.send(.openPreferences)
    session.uiContext.send(.showActivity(filter: .mentions))
    #expect(session.uiContext.pendingIntent == .showActivity(filter: .mentions))
    await authenticate(session, in: app)
    makeReady(session)
    let tabs = try #require(session.uiContext.mainForTesting?.tabs)
    #expect(tabs.selectedTab == .activity && tabs.activity.selectedFilter == .mentions)
    #expect(tabs.account.path.isEmpty)
    session.uiContext.send(.enterRestrictedMode)
    session.uiContext.send(.openPreferences)
    session.uiContext.send(.restoreAccess)
    #expect(session.uiContext.mainForTesting?.tabs === tabs)
    #expect(tabs.selectedTab == .account && tabs.account.path.count == 1)
    #expect(session.uiContext.pendingIntent == nil)
  }

  @Test func failedBackgroundWriteDoesNotMutateStore() async throws {
    let app = AppUIContext()
    let session = try #require(app.selectedSession)
    session.services.startBackgroundWrite()
    let request = try #require(app.transport.requests.first)
    app.transport.resolve(request.id, succeeded: false)
    await session.services.waitForCurrentWork()
    #expect(session.services.store.value == 0)
    #expect(session.services.pendingCount == 0)
    #expect(session.isActive)
  }

  @Test func disposedSessionIsReleasedAndRestartDoesNotRestoreMemory() async throws {
    let app = AppUIContext()
    weak var disposed = app.selectedSession
    let id = try #require(disposed?.id)
    let ending = try #require(app.endSession(id))
    _ = await ending.value
    #expect(disposed == nil)
    let restarted = AppUIContext()
    #expect(restarted.selectedSession?.id != id)
    #expect(restarted.selectedSession?.isAuthenticated == false)
    #expect(restarted.selectedSession?.services.store.value == 0)
  }

  @Test(arguments: ["setup", "preparing", "tabs", "restricted"])
  func authenticatedSessionCanBeDisposedFromEveryUIPhase(_ phase: String) async throws {
    let app = AppUIContext()
    let session = try #require(app.selectedSession)
    await authenticate(session, in: app)
    if phase != "setup" { session.uiContext.completeSetup() }
    if phase == "tabs" || phase == "restricted" { session.uiContext.finishPreparation() }
    if phase == "restricted" { session.uiContext.send(.enterRestrictedMode) }
    session.uiContext.send(.showAnnouncement)
    let ending = try #require(app.endSession(session.id))
    #expect(session.uiContext.sheet == nil)
    _ = await ending.value
    #expect(app.sessions.isEmpty)
    #expect(session.authenticatedServices == nil)
    #expect(session.services.store.isClosed)
  }

  @Test func canonicalAndLegacySchemesShareRoutingButRejectForeignURLs() {
    let parser = DeepLinkParser()
    #expect(parser.intent(for: "uicontext-demo://account/preferences") == .openPreferences)
    #expect(parser.intent(for: "uimodel-demo://account/preferences") == .openPreferences)
    #expect(parser.intent(for: "https://account/preferences") == nil)
    #expect(parser.intent(for: "uicontext-demo://unsupported/path") == nil)
  }

  private func authenticate(_ session: Session, in app: AppUIContext, as account: DemoAccount = .taylor) async {
    session.signIn(as: account)
    if let request = session.authenticationRequestID { app.transport.resolve(request) }
    await session.services.waitForCurrentWork()
  }

  private func makeReady(_ session: Session) {
    session.uiContext.completeSetup()
    session.uiContext.finishPreparation()
  }
}

private extension SessionUIContext {
  var mainForTesting: MainUIContext? {
    guard case .signedIn(let child) = authentication,
          case .main(let main) = child.phase else { return nil }
    return main
  }
}
