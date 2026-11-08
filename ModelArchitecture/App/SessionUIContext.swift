import Foundation

/// Session-owned UI topology, not the Session container or service lifetime.
/// Authentication publishes child UI scopes here; intents never authenticate.
/// Pending routing belongs to this context and is invalidated on disposal.
@MainActor
@Observable
final class SessionUIContext {
  let sessionID: UUID
  /// Authentication and termination surfaces inside one existing Session.
  enum Authentication {
    case signedOut(SignInUIContext)
    case authenticating(attemptID: UUID, account: DemoAccount)
    case signedIn(SignedInUIContext)
    case closing
    case closed
  }

  private(set) var authentication: Authentication = .signedOut(SignInUIContext())
  var sheet: SessionSheetUIContext?
  var blockingNotice: BlockingNoticeUIContext?

  private(set) var pendingIntent: UIIntent?
  private(set) var routingMessage = "No route has been handled yet."

  private let deepLinkParser = DeepLinkParser()

  init(sessionID: UUID) { self.sessionID = sessionID }

  var acceptsInput: Bool {
    switch authentication {
    case .closing, .closed: false
    default: true
    }
  }

  // MARK: - Session-owned transitions

  func beginAuthentication(attemptID: UUID, account: DemoAccount) {
    guard case .signedOut = authentication else { return }
    authentication = .authenticating(attemptID: attemptID, account: account)
  }

  func finishAuthentication(account: DemoAccount) {
    guard case .authenticating = authentication else { return }
    authentication = .signedIn(SignedInUIContext(account: account))
    routingMessage = "Created authenticated child; enclosing Session unchanged."
  }

  func failAuthentication() {
    guard case .authenticating = authentication else { return }
    authentication = .signedOut(SignInUIContext(errorMessage: "Mock authentication failed. The same Session can retry."))
  }

  /// Replaces setup with a preparing main scope.
  func completeSetup() {
    guard case .signedIn(let signedInUIContext) = authentication,
          case .setup = signedInUIContext.phase
    else { return }

    signedInUIContext.phase = .main(MainUIContext())
    routingMessage = "Created the main scope; its tabs are retained while preparation is visible."
  }

  /// Makes the retained tab tree visible and replays the latest deferred intent.
  func finishPreparation() {
    guard let mainUIContext else { return }
    mainUIContext.surface = .tabs
    routingMessage = "The tab tree is ready."
    replayPendingIntentIfNeeded()
  }

  /// Invalidates routes and presentation before service shutdown suspends.
  func beginClosing() {
    authentication = .closing
    sheet = nil
    blockingNotice = nil
    pendingIntent = nil
    routingMessage = "Closing this Session; pending intent discarded."
  }

  func finishClosing() {
    authentication = .closed
  }

  // MARK: - External routing

  /// Parses and handles an application deep link.
  @discardableResult
  func handle(url: URL) -> Bool {
    guard acceptsInput else { return false }
    let targets = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "session" } ?? []
    guard targets.isEmpty || (targets.count == 1 && targets[0].value.flatMap(UUID.init(uuidString:)) == sessionID) else {
      return false
    }
    guard let intent = deepLinkParser.intent(for: url) else {
      routingMessage = "Ignored unsupported URL: \(url.absoluteString)"
      return false
    }

    send(intent)
    return true
  }

  /// Parses URL text entered in Route Lab and handles the resulting intent.
  @discardableResult
  func handle(urlText: String) -> Bool {
    guard acceptsInput else { return false }
    guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)), handle(url: url) else {
      routingMessage = "The URL does not match a supported route."
      return false
    }
    if case .routeLab = sheet { sheet = nil }
    return true
  }

  /// Resolves a high-level request against the current UIContext tree.
  func send(_ intent: UIIntent) {
    guard acceptsInput else { return }
    if case .enterRestrictedMode = intent,
       let mainUIContext,
       case .restricted = mainUIContext.surface {
      if pendingIntent == intent {
        pendingIntent = nil
      }
      routingMessage = "Restricted mode is already the active surface."
      return
    }

    if intent.requiresReadyTabs, readyTabs == nil {
      pendingIntent = intent
      sheet = nil
      routingMessage = "Deferred \(intent.title) until the tab tree is ready."
      return
    }

    switch intent {
    case .showHome:
      guard let tabs = readyTabs else { return }
      tabs.selectedTab = .home
      tabs.home.path.removeAll()
      routingMessage = "Selected Home and replaced its path with the root path."

    case .openStory(let id):
      guard let tabs = readyTabs else { return }
      tabs.selectedTab = .home
      tabs.home.route(toStoryID: id)
      routingMessage = "Selected Home and installed the canonical story path."

    case .showActivity(let filter):
      guard let tabs = readyTabs else { return }
      tabs.selectedTab = .activity
      tabs.activity.route(to: filter)
      routingMessage = "Selected the \(filter.title) activity section."

    case .openConversation(let id):
      guard let tabs = readyTabs else { return }
      tabs.selectedTab = .messages
      tabs.messages.route(toConversationID: id)
      routingMessage = "Selected Messages and installed the canonical conversation path."

    case .showAccount:
      guard let tabs = readyTabs else { return }
      tabs.selectedTab = .account
      tabs.account.path.removeAll()
      routingMessage = "Selected Account and replaced its path with the root path."

    case .openPreferences:
      guard let tabs = readyTabs else { return }
      tabs.selectedTab = .account
      tabs.account.routeToPreferences()
      routingMessage = "Selected Account and installed the canonical preferences path."

    case .showAnnouncement:
      guard blockingNotice == nil else {
        routingMessage = "Kept the blocking layer visible instead of presenting a sheet above it."
        return
      }
      sheet = .announcement(AnnouncementUIContext())
      routingMessage = "Presented a Session-wide sheet outside the tab paths."

    case .enterRestrictedMode:
      guard let mainUIContext else { return }
      mainUIContext.surface = .restricted(RestrictionUIContext())
      routingMessage = "Replaced the visible tabs with a restricted surface; tab scopes remain alive."

    case .restoreAccess:
      guard let mainUIContext,
            case .restricted = mainUIContext.surface
      else {
        routingMessage = "Restore Access had no restricted surface to replace."
        return
      }
      mainUIContext.surface = .tabs
      routingMessage = "Restored the retained tab tree."
      replayPendingIntentIfNeeded()

    case .showBlockingNotice:
      sheet = nil
      blockingNotice = BlockingNoticeUIContext()
      routingMessage = "Presented a blocking layer in its own UI lane."
    }

    if pendingIntent == intent {
      pendingIntent = nil
    }
  }

  // MARK: - Session-wide presentations

  /// Presents Route Lab inside this Session, above its tabs.
  func presentRouteLab() {
    guard acceptsInput, blockingNotice == nil else { return }
    sheet = .routeLab(RouteLabUIContext())
  }

  /// Removes the current Session-level sheet scope.
  func dismissSheet() {
    sheet = nil
  }

  /// Removes the current blocking scope.
  func dismissBlockingNotice() {
    blockingNotice = nil
  }

  // MARK: - Diagnostics

  /// A live textual projection of the durable UIContext tree.
  var treeDescription: String {
    var lines = ["SessionUIContext"]

    switch authentication {
    case .signedOut:
      lines.append("├─ authentication: signedOut(SignInUIContext)")

    case .authenticating(_, let account):
      lines.append("├─ authentication: pending (\(account.rawValue))")

    case .closing:
      lines.append("├─ lifecycle: closing")

    case .closed:
      lines.append("├─ lifecycle: closed")

    case .signedIn(let signedInUIContext):
      lines.append("├─ authentication: signedIn(SignedInUIContext)")
      switch signedInUIContext.phase {
      case .setup(let setupUIContext):
        lines.append("│  └─ phase: setup(\(setupUIContext.step.rawValue))")

      case .main(let mainUIContext):
        lines.append("│  └─ phase: main(MainUIContext)")
        switch mainUIContext.surface {
        case .preparing:
          lines.append("│     ├─ surface: preparing")
        case .tabs:
          lines.append("│     ├─ surface: tabs")
        case .restricted:
          lines.append("│     ├─ surface: restricted")
        }
        lines.append("│     └─ retained tabs: \(tabSummary(mainUIContext.tabs))")
      }
    }

    lines.append("├─ sheet: \(sheetName)")
    lines.append("├─ blocking: \(blockingNotice == nil ? "nil" : "BlockingNoticeUIContext")")
    lines.append("└─ pendingIntent: \(pendingIntent?.title ?? "nil")")
    return lines.joined(separator: "\n")
  }

  private var mainUIContext: MainUIContext? {
    guard case .signedIn(let signedInUIContext) = authentication,
          case .main(let mainUIContext) = signedInUIContext.phase
    else { return nil }
    return mainUIContext
  }

  private var readyTabs: TabContainerUIContext? {
    guard let mainUIContext,
          case .tabs = mainUIContext.surface
    else { return nil }
    return mainUIContext.tabs
  }

  private var sheetName: String {
    switch sheet {
    case .routeLab: "RouteLabUIContext"
    case .announcement: "AnnouncementUIContext"
    case nil: "nil"
    }
  }

  private func replayPendingIntentIfNeeded() {
    guard let pendingIntent else { return }
    self.pendingIntent = nil
    send(pendingIntent)
  }

  private func tabSummary(_ tabs: TabContainerUIContext) -> String {
    [
      "selected=\(tabs.selectedTab.rawValue)",
      "home.path=\(tabs.home.path.count)",
      "activity.path=\(tabs.activity.path.count)",
      "messages.path=\(tabs.messages.path.count)",
      "account.path=\(tabs.account.path.count)",
    ].joined(separator: ", ")
  }
}
