import Foundation

/// Process-owned registry and selection, shared across windows. Creating a
/// Session is independent of login; selecting it does not recreate its owners.
/// Termination tasks outlive Views and keep closing owners alive until drained.
@MainActor
@Observable
final class AppUIContext {
  /// Bounded, value-only disposal history; never keeps the old container alive.
  struct DisposalRecord: Identifiable {
    let id: UUID
    let environment: ServiceEnvironment
    let finalValue: Int
    let replacementID: UUID?
  }

  private(set) var sessions: [Session] = []
  private(set) var selectedSessionID: UUID?
  private(set) var disposedSessions: [DisposalRecord] = []
  var isSessionLabPresented = false
  let transport = DemoTransport()
  let log = LifecycleLog()
  @ObservationIgnored private var terminations: [UUID: (replacing: Bool, task: Task<Session?, Never>)] = [:]

  var selectedSession: Session? { sessions.first { $0.id == selectedSessionID } }

  init(createInitialSession: Bool = true) {
    if createInitialSession { createSession(environment: .production) }
  }

  @discardableResult
  func createSession(environment: ServiceEnvironment, select: Bool = true) -> Session {
    let session = Session(environment: environment, transport: transport, log: log)
    sessions.append(session)
    if select { self.select(session.id) }
    return session
  }

  func select(_ id: UUID) {
    guard let session = sessions.first(where: { $0.id == id }), session.isActive else { return }
    selectedSessionID = id
    log.record("Selected; other Sessions retained", sessionID: id)
  }

  /// Duplicate requests join the existing task; conflicting disposal/replacement
  /// requests are rejected. New selection during shutdown is never overwritten.
  /// Replacement starts only after the old Session has closed its resources.
  @discardableResult
  func endSession(_ id: UUID, replacing: Bool = false) -> Task<Session?, Never>? {
    if let existing = terminations[id] {
      guard existing.replacing == replacing else {
        log.record("Rejected conflicting termination request", sessionID: id)
        return nil
      }
      return existing.task
    }
    guard let session = sessions.first(where: { $0.id == id }) else { return nil }
    let shutdown = session.terminate()
    let task = Task { [self, session] in
      await shutdown.value
      sessions.removeAll { $0.id == id }
      let replacement = replacing ? createSession(environment: session.environment, select: false) : nil
      if selectedSessionID == id {
        selectedSessionID = replacement?.id ?? sessions.first(where: \.isActive)?.id
      }
      disposedSessions.append(DisposalRecord(
        id: id, environment: session.environment,
        finalValue: session.services.store.value, replacementID: replacement?.id
      ))
      if disposedSessions.count > 10 { disposedSessions.removeFirst() }
      if let replacement {
        log.record("Replaced \(session.shortID) with a fresh Session", sessionID: replacement.id)
      }
      terminations[id] = nil
      return replacement
    }
    terminations[id] = (replacing, task)
    return task
  }

  /// An optional session query targets a specific retained Session. Without it,
  /// capture the selected destination at receipt; pending input stays in that scope.
  @discardableResult
  func handle(url: URL) -> Bool {
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let destinations = query.filter { $0.name == "session" }
    let target: Session?
    if destinations.isEmpty {
      target = selectedSession
    } else if destinations.count == 1, let value = destinations[0].value, let id = UUID(uuidString: value) {
      target = sessions.first { $0.id == id }
    } else {
      return false
    }
    guard let target, target.isActive else { return false }
    return target.uiContext.handle(url: url)
  }
}
