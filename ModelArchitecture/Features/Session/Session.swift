import Foundation

/// A container created by the app registry before authentication. Environment,
/// identity, services, and storage stay fixed through login and selection changes.
/// The registry explicitly terminates it; logout creates a different container.
@MainActor
@Observable
final class Session: Identifiable {
  let id: UUID
  let environment: ServiceEnvironment
  let uiContext: SessionUIContext
  let services: SessionServices
  private(set) var authenticatedServices: AuthenticatedServices?
  private(set) var authenticationRequestID: UUID?
  @ObservationIgnored private var terminationTask: Task<Void, Never>?
  private let log: LifecycleLog

  var isActive: Bool { services.isAcceptingWork }
  var isAuthenticated: Bool { authenticatedServices != nil && isActive }
  var shortID: String { String(id.uuidString.prefix(8)) }

  var status: String {
    switch uiContext.authentication {
    case .signedOut: "Not signed in"
    case .authenticating: "Signing in"
    case .signedIn: "Signed in as \(authenticatedServices?.account.rawValue ?? "")"
    case .closing: "Closing — waiting for callbacks"
    case .closed: "Closed"
    }
  }

  init(environment: ServiceEnvironment, transport: DemoTransport, log: LifecycleLog) {
    id = UUID()
    self.environment = environment
    self.log = log
    uiContext = SessionUIContext(sessionID: id)
    services = SessionServices(
      store: SessionStore(environment: environment, sessionID: id),
      transport: transport,
      log: log
    )
    log.record("Created \(environment.title) Session before login", sessionID: id)
  }

  /// Starts an attempt inside this existing container; the View owns no task.
  func signIn(as account: DemoAccount = .taylor) {
    guard isActive, case .signedOut = uiContext.authentication else { return }
    let attemptID = UUID()
    uiContext.beginAuthentication(attemptID: attemptID, account: account)
    authenticationRequestID = services.request("Sign in as \(account.rawValue)") { [weak self] succeeded in
      guard let self,
            self.isActive,
            case .authenticating(let currentID, _) = self.uiContext.authentication,
            currentID == attemptID
      else { return }
      self.authenticationRequestID = nil
      if succeeded {
        self.authenticatedServices = AuthenticatedServices(account: account)
        self.uiContext.finishAuthentication(account: account)
        self.log.record("Authenticated; Session identity unchanged", sessionID: self.id)
      } else {
        self.uiContext.failAuthentication()
        self.log.record("Authentication failed; Session retained", sessionID: self.id)
      }
    }
  }

  /// Idempotent termination from any authentication phase. Admission closes
  /// before this returns; the retained task completes only after all work drains.
  /// A cancellation-ignoring mock request keeps it closing until delivered.
  @discardableResult
  func terminate() -> Task<Void, Never> {
    if let terminationTask { return terminationTask }
    uiContext.beginClosing()
    services.retire()
    let task = Task { [self] in
      await services.drainAndClose()
      authenticatedServices = nil
      authenticationRequestID = nil
      uiContext.finishClosing()
      log.record("Session disposed", sessionID: id)
    }
    terminationTask = task
    return task
  }
}
