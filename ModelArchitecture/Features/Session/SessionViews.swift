import SwiftUI

/// The stateful host for the signed-out screen.
struct SignInScreen: View {
  let uiContext: SignInUIContext
  let pendingIntentTitle: String?
  let onSignIn: (DemoAccount) -> Void
  @State private var account: DemoAccount = .taylor

  var body: some View {
    SignInStateView(
      pendingIntentTitle: pendingIntentTitle,
      errorMessage: uiContext.errorMessage,
      account: $account,
      onSignIn: { onSignIn(account) }
    )
  }
}

/// A value-and-action-only rendering view for the signed-out state.
private struct SignInStateView: View {
  let pendingIntentTitle: String?
  let errorMessage: String?
  @Binding var account: DemoAccount
  let onSignIn: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      Image(systemName: "circle.hexagongrid.fill")
        .font(.system(size: 72))
        .foregroundStyle(.indigo.gradient)

      VStack(spacing: 8) {
        Text("Your Session already exists")
          .font(.title.bold())

        Text("Login is work inside this environment-bound container, not the beginning of its lifetime.")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Picker("Mock account", selection: $account) {
        ForEach(DemoAccount.allCases) { account in
          Text(account.rawValue).tag(account)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("mock-account-picker")

      if let errorMessage {
        Text(errorMessage).font(.callout).foregroundStyle(.red)
      }

      if let pendingIntentTitle {
        Label {
          Text("Queued route: \(pendingIntentTitle)")
        } icon: {
          Image(systemName: "clock.arrow.circlepath")
        }
        .font(.callout)
        .padding()
        .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
      }

      Button("Sign In", action: onSignIn)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("sign-in-button")

      Spacer()

      Text("Sessions inspects ownership and disposal. Route Lab sends intents, even before login. Authentication is simulated.")
        .font(.footnote)
        .foregroundStyle(.tertiary)
    }
    .padding(28)
    .frame(maxWidth: 560)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
  }
}

/// The stateful host for profile setup.
///
/// Form drafts are local interaction state. Only `uiContext.step`, which changes
/// the visible screen structure, is stored outside the view.
struct ProfileSetupScreen: View {
  @Bindable var uiContext: ProfileSetupUIContext
  let pendingIntentTitle: String?
  let onComplete: () -> Void

  @State private var displayName: String
  @State private var selectedTopics: Set<String> = ["Design"]

  private let topics = ["Design", "Technology", "Local", "Culture"]

  init(
    uiContext: ProfileSetupUIContext,
    initialDisplayName: String,
    pendingIntentTitle: String?,
    onComplete: @escaping () -> Void
  ) {
    self.uiContext = uiContext
    self.pendingIntentTitle = pendingIntentTitle
    self.onComplete = onComplete
    _displayName = State(initialValue: initialDisplayName)
  }

  var body: some View {
    NavigationStack {
      Form {
        if let pendingIntentTitle {
          Section {
            Label("Queued: \(pendingIntentTitle)", systemImage: "clock")
              .font(.callout)
          } footer: {
            Text("The route will run after the main tab tree becomes ready.")
          }
        }

        switch uiContext.step {
        case .profile:
          profileStateView
        case .interests:
          interestsStateView
        }
      }
      .navigationTitle(uiContext.step == .profile ? "Create Profile" : "Choose Topics")
      .navigationBarBackButtonHidden()
    }
  }

  private var profileStateView: some View {
    Group {
      Section("Profile") {
        TextField("Display name", text: $displayName)
          .textContentType(.name)
          .accessibilityIdentifier("profile-display-name")
      }

      Section {
        Button("Continue", action: uiContext.continueToInterests)
          .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
          .accessibilityIdentifier("setup-continue-button")
      } footer: {
        Text("The text draft is local @State; it is not needed for external routing.")
      }
    }
  }

  private var interestsStateView: some View {
    Group {
      Section("Topics") {
        ForEach(topics, id: \.self) { topic in
          Button {
            if selectedTopics.contains(topic) {
              selectedTopics.remove(topic)
            } else {
              selectedTopics.insert(topic)
            }
          } label: {
            HStack {
              Text(topic)
                .foregroundStyle(.primary)
              Spacer()
              if selectedTopics.contains(topic) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.indigo)
              }
            }
          }
        }
      }

      Section {
        Button("Finish Setup", action: onComplete)
          .disabled(selectedTopics.isEmpty)
          .accessibilityIdentifier("finish-setup-button")
      }
    }
  }
}
