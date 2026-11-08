import SwiftUI

/// Selects the visible subtree within a signed-in session.
struct SignedInScreen: View {
  @Bindable var uiContext: SignedInUIContext
  let pendingIntentTitle: String?
  let onCompleteSetup: () -> Void
  let onFinishPreparation: () -> Void
  let onSendIntent: (UIIntent) -> Void
  let onSignOut: () -> Void

  var body: some View {
    switch uiContext.phase {
    case .setup(let setupUIContext):
      ProfileSetupScreen(
        uiContext: setupUIContext,
        initialDisplayName: uiContext.account.rawValue,
        pendingIntentTitle: pendingIntentTitle,
        onComplete: onCompleteSetup
      )

    case .main(let mainUIContext):
      MainScreen(
        uiContext: mainUIContext,
        accountName: uiContext.account.rawValue,
        pendingIntentTitle: pendingIntentTitle,
        onFinishPreparation: onFinishPreparation,
        onSendIntent: onSendIntent,
        onSignOut: onSignOut
      )
    }
  }
}

/// Selects the active surface within the main UI scope.
struct MainScreen: View {
  @Bindable var uiContext: MainUIContext
  let accountName: String
  let pendingIntentTitle: String?
  let onFinishPreparation: () -> Void
  let onSendIntent: (UIIntent) -> Void
  let onSignOut: () -> Void

  var body: some View {
    switch uiContext.surface {
    case .preparing(let preparationUIContext):
      PreparationScreen(
        uiContext: preparationUIContext,
        pendingIntentTitle: pendingIntentTitle,
        onFinish: onFinishPreparation
      )

    case .tabs:
      TabContainerScreen(
        uiContext: uiContext.tabs,
        accountName: accountName,
        onSendIntent: onSendIntent,
        onSignOut: onSignOut
      )

    case .restricted(let restrictionUIContext):
      RestrictionScreen(
        uiContext: restrictionUIContext,
        pendingIntentTitle: pendingIntentTitle,
        onRestore: { onSendIntent(.restoreAccess) },
        onSignOut: onSignOut
      )
    }
  }
}

/// Renders the explicit preparation surface before tabs become routable.
private struct PreparationScreen: View {
  let uiContext: PreparationUIContext
  let pendingIntentTitle: String?
  let onFinish: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      ProgressView()
        .controlSize(.large)

      Text("Preparing Your Space")
        .font(.largeTitle.bold())

      Text(uiContext.message)
        .foregroundStyle(.secondary)

      if let pendingIntentTitle {
        Label("Waiting to run: \(pendingIntentTitle)", systemImage: "clock")
          .font(.callout)
          .padding()
          .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
      }

      Button("Enter App", action: onFinish)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("enter-app-button")
    }
    .padding(28)
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
  }
}

/// Renders a replacement main surface while keeping the tab tree retained.
private struct RestrictionScreen: View {
  let uiContext: RestrictionUIContext
  let pendingIntentTitle: String?
  let onRestore: () -> Void
  let onSignOut: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "lock.shield")
        .font(.system(size: 58))
        .foregroundStyle(.orange)

      Text(uiContext.title)
        .font(.largeTitle.bold())

      Text(uiContext.message)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if let pendingIntentTitle {
        Label("Queued: \(pendingIntentTitle)", systemImage: "clock")
          .font(.callout)
      }

      Button("Restore Access", action: onRestore)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

      Button("Sign Out", role: .destructive, action: onSignOut)
    }
    .padding(28)
    .frame(maxWidth: 540)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
  }
}
