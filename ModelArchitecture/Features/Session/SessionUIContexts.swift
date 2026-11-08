import Foundation

/// The UI scope for the signed-out welcome screen.
///
/// The Session owns this child through its UIContext before authentication.
@MainActor
@Observable
final class SignInUIContext {
  let errorMessage: String?

  init(errorMessage: String? = nil) { self.errorMessage = errorMessage }
}

/// The UI scope for the two-step first-run setup flow.
///
/// The current step is externally represented because it changes the screen
/// structure. Text-field drafts and selections remain local to the stateful view.
@MainActor
@Observable
final class ProfileSetupUIContext {
  /// Mutually exclusive screens within the setup scope.
  enum Step: String, Sendable {
    case profile
    case interests
  }

  var step: Step = .profile

  /// Moves from the profile form to the interests form.
  func continueToInterests() {
    step = .interests
  }

  /// Moves back to the profile form without recreating the setup scope.
  func returnToProfile() {
    step = .profile
  }
}

/// The authenticated UI child, created after login inside an existing Session.
/// It is removed on termination; it does not define the Session's lifetime.
@MainActor
@Observable
final class SignedInUIContext {
  /// Mutually exclusive top-level phases of a signed-in session.
  enum Phase {
    case setup(ProfileSetupUIContext)
    case main(MainUIContext)
  }

  var phase: Phase
  let account: DemoAccount

  init(account: DemoAccount, phase: Phase? = nil) {
    self.account = account
    self.phase = phase ?? .setup(ProfileSetupUIContext())
  }
}
