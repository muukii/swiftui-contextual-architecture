import SwiftUI

/// Projects registry selection without giving a View ownership of a Session.
struct AppRootView: View {
  @Bindable var uiContext: AppUIContext

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          if let session = uiContext.selectedSession {
            Text("\(session.environment.title) · \(session.shortID)")
              .font(.subheadline.monospaced().bold())
              .accessibilityIdentifier("selected-session-identity")
            Text(session.status)
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text("No Session selected").font(.headline)
          }
        }
        Spacer(minLength: 0)
        Button {
          uiContext.isSessionLabPresented = true
        } label: {
          Label("Sessions", systemImage: "square.stack.3d.up")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("session-lab-button")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.bar)

      Divider()

      if let session = uiContext.selectedSession {
        SessionRootView(session: session, appContext: uiContext)
          .id(session.id)
      } else {
        ContentUnavailableView {
          Label("No active Session selected", systemImage: "square.stack.3d.up.slash")
        } description: {
          Text("Create a container for an environment. Login happens inside it later.")
        } actions: {
          Button("Open Session Lab") { uiContext.isSessionLabPresented = true }
            .buttonStyle(.borderedProminent)
        }
      }
    }
    .sheet(isPresented: $uiContext.isSessionLabPresented) {
      SessionLabScreen(uiContext: uiContext)
    }
  }
}

#Preview {
  AppRootView(uiContext: AppUIContext())
}
