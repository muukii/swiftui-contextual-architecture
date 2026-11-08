import Foundation

/// A fixed service destination chosen before a Session is constructed.
enum ServiceEnvironment: String, CaseIterable, Identifiable, Sendable {
  case production
  case staging

  var id: Self { self }
  var title: String { rawValue.capitalized }
}

/// Sample identities, not credentials or evidence of real authentication.
enum DemoAccount: String, CaseIterable, Identifiable, Sendable {
  case taylor = "Taylor"
  case jordan = "Jordan"

  var id: Self { self }
}

/// App-owned diagnostic values; entries never retain a Session or its services.
@MainActor
@Observable
final class LifecycleLog {
  /// A value snapshot retained in the process-level diagnostic history.
  struct Entry: Identifiable {
    let id = UUID()
    let sessionID: UUID
    let message: String
  }

  private(set) var entries: [Entry] = []

  func record(_ message: String, sessionID: UUID) {
    entries.append(Entry(sessionID: sessionID, message: message))
    if entries.count > 100 { entries.removeFirst() }
  }
}

/// A manually released callback used to model an SDK that ignores cancellation.
/// The transport retains it until delivery; exactly one service task awaits it.
@MainActor
final class DemoRequest: Identifiable {
  let id = UUID()
  let sessionID: UUID
  let title: String
  private var result: Bool?
  private var continuation: CheckedContinuation<Bool, Never>?

  init(sessionID: UUID, title: String) {
    self.sessionID = sessionID
    self.title = title
  }

  func response() async -> Bool {
    if let result { return result }
    return await withCheckedContinuation { continuation = $0 }
  }

  func resolve(succeeded: Bool) {
    guard result == nil else { return }
    result = succeeded
    continuation?.resume(returning: succeeded)
    continuation = nil
  }
}

/// App-owned test transport, not shared account state. Session services issue
/// requests; the lab releases them deterministically, even after cancellation.
@MainActor
@Observable
final class DemoTransport {
  private(set) var requests: [DemoRequest] = []

  func issue(sessionID: UUID, title: String) -> DemoRequest {
    let request = DemoRequest(sessionID: sessionID, title: title)
    requests.append(request)
    return request
  }

  func resolve(_ id: UUID, succeeded: Bool = true) {
    guard let request = requests.first(where: { $0.id == id }) else { return }
    requests.removeAll { $0.id == id }
    request.resolve(succeeded: succeeded)
  }

  func resolveAll() {
    for request in requests { resolve(request.id) }
  }
}

/// In-memory storage bound at Session creation, including before login.
/// Retirement rejects new writes; close happens only after owned work drains.
/// No files or credentials are persisted or deleted by this demo.
@MainActor
@Observable
final class SessionStore {
  let id = UUID()
  let environment: ServiceEnvironment
  let sessionID: UUID
  private(set) var value = 0
  private(set) var isRetired = false
  private(set) var isClosed = false

  var namespace: String { "Environments/\(environment.rawValue)/Sessions/\(sessionID.uuidString)" }

  init(environment: ServiceEnvironment, sessionID: UUID) {
    self.environment = environment
    self.sessionID = sessionID
  }

  @discardableResult
  func increment() -> Bool {
    guard !isRetired, !isClosed else { return false }
    value += 1
    return true
  }

  func retire() { isRetired = true }
  func close() { isClosed = true }
}

/// Session-owned pre-login services. Owns every request task and its fixed store.
/// Retirement closes admission synchronously; drainAndClose waits for even
/// cancellation-ignoring callbacks before closing the store. Repeated calls are safe.
@MainActor
@Observable
final class SessionServices {
  let id = UUID()
  let store: SessionStore
  private(set) var isAcceptingWork = true
  private(set) var pendingCount = 0
  @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
  private let transport: DemoTransport
  private let log: LifecycleLog

  init(store: SessionStore, transport: DemoTransport, log: LifecycleLog) {
    self.store = store
    self.transport = transport
    self.log = log
  }

  @discardableResult
  func request(_ title: String, completion: @escaping @MainActor (Bool) -> Void) -> UUID? {
    guard isAcceptingWork else { return nil }
    let request = transport.issue(sessionID: store.sessionID, title: title)
    log.record("Started \(title)", sessionID: store.sessionID)
    tasks[request.id] = Task { [weak self] in
      let succeeded = await request.response()
      guard let self else { return }
      defer {
        self.tasks[request.id] = nil
        self.pendingCount = self.tasks.count
      }
      guard self.isAcceptingWork, !Task.isCancelled else {
        self.log.record("Rejected late callback: \(title)", sessionID: self.store.sessionID)
        return
      }
      completion(succeeded)
    }
    pendingCount = tasks.count
    return request.id
  }

  func increment() {
    guard isAcceptingWork, store.increment() else { return }
    log.record("Stored value = \(store.value)", sessionID: store.sessionID)
  }

  func startBackgroundWrite() {
    request("Background write") { [weak self] succeeded in
      guard let self else { return }
      if succeeded { self.increment() }
      else { self.log.record("Background write failed", sessionID: self.store.sessionID) }
    }
  }

  func retire() {
    guard isAcceptingWork else { return }
    isAcceptingWork = false
    store.retire()
    for task in tasks.values { task.cancel() }
    log.record("Admission closed; cancellation requested", sessionID: store.sessionID)
  }

  func drainAndClose() async {
    retire()
    let inFlight = Array(tasks.values)
    for task in inFlight { await task.value }
    guard !store.isClosed else { return }
    store.close()
    log.record("Work drained; store closed", sessionID: store.sessionID)
  }

  /// Joins the current batch without ending the Session, for deterministic checks.
  func waitForCurrentWork() async {
    let inFlight = Array(tasks.values)
    for task in inFlight { await task.value }
  }
}

/// Authenticated-only dependencies created by a successful attempt, never at
/// Session construction. The Session releases this child after shutdown drains.
@MainActor
final class AuthenticatedServices {
  let id = UUID()
  let account: DemoAccount

  init(account: DemoAccount) { self.account = account }
}
