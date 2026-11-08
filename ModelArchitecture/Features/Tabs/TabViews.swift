import SwiftUI

/// Renders four retained tab hosts and binds their shared selection.
struct TabContainerScreen: View {
  @Bindable var uiContext: TabContainerUIContext
  let accountName: String
  let onSendIntent: (UIIntent) -> Void
  let onSignOut: () -> Void

  var body: some View {
    TabView(selection: $uiContext.selectedTab) {
      HomeScreen(
        uiContext: uiContext.home,
        onShowAnnouncement: { onSendIntent(.showAnnouncement) }
      )
      .tabItem {
        Label(TabContainerUIContext.Tab.home.title, systemImage: TabContainerUIContext.Tab.home.symbol)
      }
      .tag(TabContainerUIContext.Tab.home)

      ActivityScreen(uiContext: uiContext.activity)
        .tabItem {
          Label(
            TabContainerUIContext.Tab.activity.title,
            systemImage: TabContainerUIContext.Tab.activity.symbol
          )
        }
        .tag(TabContainerUIContext.Tab.activity)

      MessagesScreen(uiContext: uiContext.messages)
        .tabItem {
          Label(
            TabContainerUIContext.Tab.messages.title,
            systemImage: TabContainerUIContext.Tab.messages.symbol
          )
        }
        .tag(TabContainerUIContext.Tab.messages)

      AccountScreen(
        uiContext: uiContext.account,
        accountName: accountName,
        onEnterRestrictedMode: { onSendIntent(.enterRestrictedMode) },
        onSignOut: onSignOut
      )
      .tabItem {
        Label(
          TabContainerUIContext.Tab.account.title,
          systemImage: TabContainerUIContext.Tab.account.symbol
        )
      }
      .tag(TabContainerUIContext.Tab.account)
    }
  }
}

/// The stateful host for Home and its navigation stack.
struct HomeScreen: View {
  @Bindable var uiContext: HomeUIContext
  let onShowAnnouncement: () -> Void

  var body: some View {
    NavigationStack(path: $uiContext.path) {
      HomeStateView(stories: uiContext.stories, onSelect: uiContext.open)
        .navigationTitle("Home")
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button(action: onShowAnnouncement) {
              Image(systemName: "megaphone")
            }
            .accessibilityLabel("Show Announcement")
          }
        }
        .navigationDestination(for: HomeUIContext.Destination.self) { destination in
          switch destination {
          case .story(let storyUIContext):
            StoryScreen(uiContext: storyUIContext)
          }
        }
    }
  }
}

/// A value-and-action-only rendering view for the Home root.
private struct HomeStateView: View {
  let stories: [SampleStory]
  let onSelect: (SampleStory) -> Void

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 14) {
        ForEach(stories) { story in
          Button {
            onSelect(story)
          } label: {
            HStack(spacing: 16) {
              Image(systemName: story.symbol)
                .font(.title2)
                .frame(width: 48, height: 48)
                .foregroundStyle(story.tint)
                .background(story.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

              VStack(alignment: .leading, spacing: 5) {
                Text(story.title)
                  .font(.headline)
                  .foregroundStyle(.primary)
                  .multilineTextAlignment(.leading)

                Text(story.summary)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
                  .multilineTextAlignment(.leading)
              }

              Spacer(minLength: 0)

              Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("story-\(story.id)")
        }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
  }
}

/// The stateful host for a story UI scope stored in Home's path.
private struct StoryScreen: View {
  @Bindable var uiContext: StoryUIContext

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Image(systemName: uiContext.story.symbol)
          .font(.system(size: 52))
          .foregroundStyle(uiContext.story.tint)

        Text(uiContext.story.title)
          .font(.largeTitle.bold())

        Text(uiContext.story.summary)
          .font(.title3)
          .foregroundStyle(.secondary)

        Divider()

        Text("The navigation path owns this StoryUIContext instance. Bookmark state survives tab switches and disappears naturally when the path is popped.")
          .font(.body)

        Toggle("Bookmarked", isOn: $uiContext.isBookmarked)
          .padding()
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
      }
      .padding(24)
    }
    .navigationTitle("Story")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// The stateful host for Activity, its section selection, and its path.
struct ActivityScreen: View {
  @Bindable var uiContext: ActivityUIContext

  var body: some View {
    NavigationStack(path: $uiContext.path) {
      List {
        Section {
          Picker("Activity section", selection: $uiContext.selectedFilter) {
            ForEach(ActivityFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("activity-filter")
        }

        Section(uiContext.selectedFilter.title) {
          ForEach(uiContext.visibleActivities) { activity in
            Button {
              uiContext.open(activity)
            } label: {
              Label {
                VStack(alignment: .leading, spacing: 4) {
                  Text(activity.title)
                    .foregroundStyle(.primary)
                  Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              } icon: {
                Image(systemName: activity.symbol)
                  .foregroundStyle(.indigo)
              }
            }
          }
        }
      }
      .navigationTitle("Activity")
      .navigationDestination(for: ActivityUIContext.Destination.self) { destination in
        switch destination {
        case .detail(let detailUIContext):
          ActivityDetailScreen(uiContext: detailUIContext)
        }
      }
    }
  }
}

/// Renders a child UI scope stored in Activity's path.
private struct ActivityDetailScreen: View {
  let uiContext: ActivityDetailUIContext

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: uiContext.activity.symbol)
        .font(.system(size: 48))
        .foregroundStyle(.indigo)

      Text(uiContext.activity.title)
        .font(.title2.bold())
        .multilineTextAlignment(.center)

      Text(uiContext.activity.detail)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .navigationTitle("Activity Detail")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// The stateful host for Messages and its navigation stack.
struct MessagesScreen: View {
  @Bindable var uiContext: MessagesUIContext

  var body: some View {
    NavigationStack(path: $uiContext.path) {
      List(uiContext.conversations) { conversation in
        Button {
          uiContext.open(conversation)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: conversation.symbol)
              .font(.title3)
              .frame(width: 42, height: 42)
              .background(.indigo.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
              Text(conversation.title)
                .font(.headline)
                .foregroundStyle(.primary)
              Text(conversation.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .accessibilityIdentifier("conversation-\(conversation.id)")
      }
      .navigationTitle("Messages")
      .navigationDestination(for: MessagesUIContext.Destination.self) { destination in
        switch destination {
        case .conversation(let conversationUIContext):
          ConversationScreen(uiContext: conversationUIContext)
        }
      }
    }
  }
}

/// The stateful host for a conversation scope.
///
/// The composer draft and focus are local interaction state. Committed messages
/// are sent to the path-owned `ConversationUIContext`.
private struct ConversationScreen: View {
  @Bindable var uiContext: ConversationUIContext
  @State private var draft = ""
  @FocusState private var composerIsFocused: Bool

  var body: some View {
    ConversationStateView(
      messages: uiContext.messages,
      draft: $draft,
      composerIsFocused: $composerIsFocused,
      onSend: sendDraft
    )
    .navigationTitle(uiContext.conversation.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func sendDraft() {
    uiContext.send(draft)
    draft = ""
  }
}

/// A rendering view for conversation values and actions.
private struct ConversationStateView: View {
  let messages: [SampleMessage]
  @Binding var draft: String
  var composerIsFocused: FocusState<Bool>.Binding
  let onSend: () -> Void

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 10) {
        ForEach(messages) { message in
          HStack {
            if message.isFromCurrentUser { Spacer(minLength: 44) }

            Text(message.text)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .foregroundStyle(message.isFromCurrentUser ? .white : .primary)
              .background(
                message.isFromCurrentUser ? Color.indigo : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
              )

            if !message.isFromCurrentUser { Spacer(minLength: 44) }
          }
        }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 10) {
        TextField("Message", text: $draft, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .focused(composerIsFocused)

        Button("Send", action: onSend)
          .buttonStyle(.borderedProminent)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding()
      .background(.bar)
    }
  }
}

/// The stateful host for Account and its navigation stack.
struct AccountScreen: View {
  @Bindable var uiContext: AccountUIContext
  let accountName: String
  let onEnterRestrictedMode: () -> Void
  let onSignOut: () -> Void

  var body: some View {
    NavigationStack(path: $uiContext.path) {
      List {
        Section("Profile") {
          Label(accountName, systemImage: "person.crop.circle.fill")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accountName)
            .accessibilityIdentifier("account-name")
          Label("Community Member", systemImage: "checkmark.seal")
        }

        Section("Navigation") {
          Button("Preferences", action: uiContext.openPreferences)
            .accessibilityIdentifier("open-preferences-button")
        }

        Section("App surfaces") {
          Button("Enter Restricted Mode", action: onEnterRestrictedMode)
          Button("Log Out & Replace Session", role: .destructive, action: onSignOut)
            .accessibilityIdentifier("logout-replace-button")
        }
      }
      .navigationTitle("Account")
      .navigationDestination(for: AccountUIContext.Destination.self) { destination in
        switch destination {
        case .preferences(let preferencesUIContext):
          PreferencesScreen(uiContext: preferencesUIContext)
        }
      }
    }
  }
}

/// The stateful host for a preferences scope stored in Account's path.
private struct PreferencesScreen: View {
  @Bindable var uiContext: PreferencesUIContext

  var body: some View {
    Form {
      Section("Notifications") {
        Toggle("Notifications", isOn: $uiContext.notificationsEnabled)
      }

      Section("Appearance") {
        Toggle("Compact Appearance", isOn: $uiContext.compactAppearance)
      }

      Section {
        Text("This PreferencesUIContext exists only while its destination remains in Account's path.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Preferences")
  }
}

private extension SampleStory {
  var tint: Color {
    switch tintName {
    case "green": .green
    case "orange": .orange
    case "blue": .blue
    default: .indigo
    }
  }
}
