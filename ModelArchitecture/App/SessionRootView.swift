import SwiftUI

/// Projects one Session's UI; lifecycle actions go to its owner and registry.
struct SessionRootView: View {
  @Bindable var uiContext: SessionUIContext
  let session: Session
  let appContext: AppUIContext

  init(session: Session, appContext: AppUIContext) {
    self.session = session
    self.appContext = appContext
    self.uiContext = session.uiContext
  }

  var body: some View {
    ZStack {
      sessionContent

      if session.isActive {
        routeLabButton
          .zIndex(1)
      }

      if let blockingNotice = uiContext.blockingNotice {
        BlockingNoticeView(
          uiContext: blockingNotice,
          onDismiss: uiContext.dismissBlockingNotice
        )
        .transition(.opacity)
        .zIndex(2)
      }
    }
    .sheet(item: $uiContext.sheet) { sheet in
      sheetContent(sheet)
    }
    .animation(.easeInOut(duration: 0.2), value: uiContext.blockingNotice?.id)
  }

  private var routeLabButton: some View {
    VStack {
      Spacer()
      HStack {
        Spacer()
        Button(action: uiContext.presentRouteLab) {
          Label("Route Lab", systemImage: "point.3.connected.trianglepath.dotted")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .padding(.trailing, 16)
        .padding(.bottom, 72)
        .accessibilityIdentifier("route-lab-button")
      }
    }
  }

  @ViewBuilder
  private var sessionContent: some View {
    switch uiContext.authentication {
    case .signedOut(let signInUIContext):
      SignInScreen(
        uiContext: signInUIContext,
        pendingIntentTitle: uiContext.pendingIntent?.title,
        onSignIn: session.signIn
      )

    case .authenticating(_, let account):
      VStack(spacing: 20) {
        ProgressView().controlSize(.large)
        Text("Signing in as \(account.rawValue)").font(.title2.bold())
        Text("This mock waits for you. The Session ID, services, and storage already exist and will stay the same after login.")
          .foregroundStyle(.secondary)
        Button("Complete Sign In") { resolveAuthentication(succeeded: true) }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("complete-sign-in-button")
        Button("Fail Sign In") { resolveAuthentication(succeeded: false) }
        Button("Dispose During Sign In", role: .destructive) {
          appContext.endSession(session.id)
        }
        .accessibilityIdentifier("dispose-during-sign-in-button")
      }
      .padding(28)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .closing, .closed:
      VStack(spacing: 20) {
        ProgressView().controlSize(.large)
        Text("Closing Session \(session.shortID)").font(.title2.bold())
        Text("New work is blocked. The mock SDK ignores cancellation, so shutdown waits for its callbacks before closing storage.")
          .foregroundStyle(.secondary)
        Text("In flight: \(session.services.pendingCount)")
          .font(.callout.monospaced())
        Button("Deliver Pending Callbacks") {
          for request in appContext.transport.requests where request.sessionID == session.id {
            appContext.transport.resolve(request.id)
          }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("deliver-closing-callbacks-button")
        Text("Their results will be rejected. No new Session receives this Session's pending routes.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding(28)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .signedIn(let signedInUIContext):
      SignedInScreen(
        uiContext: signedInUIContext,
        pendingIntentTitle: uiContext.pendingIntent?.title,
        onCompleteSetup: uiContext.completeSetup,
        onFinishPreparation: uiContext.finishPreparation,
        onSendIntent: uiContext.send,
        onSignOut: { appContext.endSession(session.id, replacing: true) }
      )
    }
  }

  @ViewBuilder
  private func sheetContent(_ sheet: SessionSheetUIContext) -> some View {
    switch sheet {
    case .routeLab(let routeLabUIContext):
      RouteLabScreen(
        uiContext: routeLabUIContext,
        sessionUIContext: uiContext,
        onReplaceSession: { appContext.endSession(session.id, replacing: true) }
      )

    case .announcement(let announcementUIContext):
      AnnouncementScreen(
        uiContext: announcementUIContext,
        onDismiss: uiContext.dismissSheet
      )
    }
  }

  private func resolveAuthentication(succeeded: Bool) {
    guard let requestID = session.authenticationRequestID else { return }
    appContext.transport.resolve(requestID, succeeded: succeeded)
  }
}

/// Renders an Session-wide announcement sheet.
private struct AnnouncementScreen: View {
  let uiContext: AnnouncementUIContext
  let onDismiss: () -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "megaphone.fill")
          .font(.system(size: 54))
          .foregroundStyle(.indigo)

        Text(uiContext.title)
          .font(.title2.bold())
          .multilineTextAlignment(.center)

        Text(uiContext.message)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Text("Every tab path stays exactly as it was.")
          .font(.callout.monospaced())
          .padding()
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
      }
      .padding(28)
      .navigationTitle("Announcement")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onDismiss)
        }
      }
    }
    .presentationDetents([.medium])
  }
}

/// Renders the independent blocking lane above the current session and sheets.
private struct BlockingNoticeView: View {
  let uiContext: BlockingNoticeUIContext
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .ignoresSafeArea()

      VStack(spacing: 18) {
        Image(systemName: "exclamationmark.shield.fill")
          .font(.system(size: 44))
          .foregroundStyle(.orange)

        Text(uiContext.title)
          .font(.title2.bold())

        Text(uiContext.message)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        Button("Acknowledge", action: onDismiss)
          .buttonStyle(.borderedProminent)
      }
      .padding(28)
      .frame(maxWidth: 360)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
      .padding()
    }
    .accessibilityAddTraits(.isModal)
  }
}
