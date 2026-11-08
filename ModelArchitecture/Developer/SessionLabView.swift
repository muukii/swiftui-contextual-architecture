import SwiftUI

/// Registry-level diagnostics and deterministic mock controls. Presentation and
/// inspector selection are View-local; Session ownership stays in AppUIContext.
struct SessionLabScreen: View {
  @Bindable var uiContext: AppUIContext
  @State private var environment: ServiceEnvironment = .production
  @State private var page: Page = .sessions

  /// View-local inspector selection, unrelated to Session ownership.
  private enum Page: String, CaseIterable, Identifiable {
    case sessions = "Sessions"
    case callbacks = "Callbacks"
    case events = "Events"
    var id: Self { self }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Inspector", selection: $page) {
          ForEach(Page.allCases) { page in Text(page.rawValue).tag(page) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("session-lab-pages")
        .padding()

        List {
          switch page {
          case .sessions: sessionsPage
          case .callbacks: callbacksPage
          case .events: eventsPage
          }
        }
        .accessibilityIdentifier("session-lab-list")
      }
      .navigationTitle("Session Lab")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { uiContext.isSessionLabPresented = false }
        }
      }
    }
  }

  @ViewBuilder
  private var sessionsPage: some View {
    if let session = uiContext.selectedSession {
      Section("Selected container") {
        LabeledContent("Environment", value: session.environment.title)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Environment")
          .accessibilityValue(session.environment.title)
          .accessibilityIdentifier("session-environment")
        LabeledContent("Session ID", value: session.shortID)
          .accessibilityIdentifier("inspected-session-id")
        Text(session.status).foregroundStyle(session.isActive ? .primary : .secondary)
        LabeledContent("Stored value", value: "\(session.services.store.value)")
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Stored value")
          .accessibilityValue("\(session.services.store.value)")
          .accessibilityIdentifier("session-store-value")

        DisclosureGroup("Ownership details") {
          identifier("Session", session.id, accessibilityID: "ownership-session-id")
          identifier("Pre-login services", session.services.id, accessibilityID: "ownership-services-id")
          identifier("Storage", session.services.store.id, accessibilityID: "ownership-storage-id")
          if let authenticated = session.authenticatedServices {
            identifier("Authenticated services", authenticated.id, accessibilityID: "ownership-authenticated-id")
          } else {
            Text("Authenticated services: not created")
          }
          Text(session.services.store.namespace)
            .font(.caption.monospaced())
            .textSelection(.enabled)
          Text("In-memory only. This namespace does not create a directory.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }

      Section {
        Button("Increment Session Value", action: session.services.increment)
          .accessibilityIdentifier("increment-session-value-button")
        Button("Start Background Write", action: session.services.startBackgroundWrite)
          .accessibilityIdentifier("start-background-write-button")
        if session.isAuthenticated {
          Button("Log Out & Replace Session", role: .destructive) {
            uiContext.endSession(session.id, replacing: true)
          }
          .accessibilityIdentifier("lab-logout-replace-button")
        }
        Button("Dispose Session", role: .destructive) {
          uiContext.endSession(session.id)
        }
        .accessibilityIdentifier("dispose-session-button")
      } header: {
        Text("Session-scoped operations")
      } footer: {
        Text(session.isActive
          ? "Work is available before login and remains owned when deselected. Complete asynchronous work in Callbacks."
          : "Admission is closed. Deliver outstanding callbacks to finish draining; their results will be rejected.")
      }
      .disabled(!session.isActive)
    }

    Section {
      ForEach(uiContext.sessions) { session in
        Button {
          uiContext.select(session.id)
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("\(session.environment.title) · \(session.shortID)")
                .font(.subheadline.monospaced().bold())
              Text(session.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if uiContext.selectedSessionID == session.id {
              Image(systemName: "checkmark.circle.fill")
            }
          }
        }
        .disabled(!session.isActive)
        .accessibilityIdentifier("select-session-\(session.id.uuidString)")
      }
      if uiContext.sessions.isEmpty {
        Text("No retained Sessions").foregroundStyle(.secondary)
      }
    } header: {
      Text("Retained containers (\(uiContext.sessions.count))")
        .accessibilityIdentifier("retained-session-count")
        .accessibilityValue("\(uiContext.sessions.count)")
    } footer: {
      Text("Selection is not ownership. Unauthenticated containers are Sessions too.")
    }

    Section {
      Picker("Environment", selection: $environment) {
        ForEach(ServiceEnvironment.allCases) { environment in
          Text(environment.title).tag(environment)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("new-session-environment")
      Button("Create Session") {
        uiContext.createSession(environment: environment)
      }
      .accessibilityIdentifier("create-session-button")
    } header: {
      Text("New container")
    } footer: {
      Text("The environment is fixed at creation. Creating another Session never signs out the existing ones.")
    }
  }

  @ViewBuilder
  private var callbacksPage: some View {
    Section {
      Text("These mock requests deliberately ignore cancellation. Deliver a callback after disposing its Session to observe rejection and shutdown draining.")
        .font(.callout)
      Button("Deliver All Callbacks", action: uiContext.transport.resolveAll)
        .disabled(uiContext.transport.requests.isEmpty)
        .accessibilityIdentifier("deliver-all-callbacks-button")
    }
    ForEach(uiContext.transport.requests) { request in
      Section {
        Text(request.title).font(.headline)
        Text("Session \(request.sessionID.uuidString.prefix(8))")
          .font(.caption.monospaced())
        HStack {
          Button("Deliver Success") { uiContext.transport.resolve(request.id) }
            .buttonStyle(.borderedProminent)
          Button("Deliver Failure") { uiContext.transport.resolve(request.id, succeeded: false) }
            .buttonStyle(.bordered)
        }
      }
    }
    if uiContext.transport.requests.isEmpty {
      Text("No pending callbacks").foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var eventsPage: some View {
    if !uiContext.disposedSessions.isEmpty {
      Section("Disposed containers") {
        ForEach(uiContext.disposedSessions.reversed()) { record in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(record.environment.title) · \(record.id.uuidString.prefix(8))")
              .font(.subheadline.monospaced().bold())
            Text("Closed · final stored value: \(record.finalValue)")
            if let replacement = record.replacementID {
              Text("Replacement: \(replacement.uuidString.prefix(8))")
                .font(.caption.monospaced())
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("disposed-session-\(record.id.uuidString)")
          .accessibilityValue("\(record.finalValue)")
        }
      }
    }
    Section("Lifecycle events · newest first") {
      ForEach(uiContext.log.entries.reversed()) { entry in
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.message).font(.callout)
          Text(entry.sessionID.uuidString.prefix(8))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-event-\(entry.sessionID.uuidString)")
      }
    }
  }

  private func identifier(_ title: String, _ id: UUID, accessibilityID: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
        .accessibilityIdentifier(accessibilityID)
    }
  }
}
