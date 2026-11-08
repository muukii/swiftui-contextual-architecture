import Foundation

/// Owns the selected tab and all four retained tab UI scopes.
///
/// The child UIContexts are created once. Switching tabs changes visibility only;
/// it does not discard another tab's navigation path or screen state.
@MainActor
@Observable
final class TabContainerUIContext {
  /// The stable, externally addressable tabs in the prototype.
  enum Tab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case activity
    case messages
    case account

    var id: Self { self }

    var title: String {
      rawValue.capitalized
    }

    var symbol: String {
      switch self {
      case .home: "house"
      case .activity: "bell"
      case .messages: "bubble.left.and.bubble.right"
      case .account: "person.crop.circle"
      }
    }
  }

  var selectedTab: Tab = .home
  let home = HomeUIContext()
  let activity = ActivityUIContext()
  let messages = MessagesUIContext()
  let account = AccountUIContext()
}

/// Owns Home's ordered navigation stack.
@MainActor
@Observable
final class HomeUIContext {
  /// Screens pushed above the Home root.
  enum Destination: Hashable {
    case story(StoryUIContext)
  }

  var path: [Destination] = []
  let stories = SampleContent.stories

  /// Pushes a story as an in-app navigation action.
  func open(_ story: SampleStory) {
    path.append(.story(StoryUIContext(story: story)))
  }

  /// Replaces the stack with the canonical path for an external route.
  func route(toStoryID id: String) {
    path = [.story(StoryUIContext(story: SampleContent.story(id: id)))]
  }
}

/// The stateful child scope stored directly in Home's navigation path.
@MainActor
@Observable
final class StoryUIContext: Identifiable, Hashable {
  nonisolated let id: String
  let story: SampleStory
  var isBookmarked = false

  init(story: SampleStory) {
    self.id = story.id
    self.story = story
  }

  nonisolated static func == (lhs: StoryUIContext, rhs: StoryUIContext) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

/// Owns Activity's selected section and ordered navigation stack.
@MainActor
@Observable
final class ActivityUIContext {
  /// Screens pushed above the Activity root.
  enum Destination: Hashable {
    case detail(ActivityDetailUIContext)
  }

  var selectedFilter: ActivityFilter = .all
  var path: [Destination] = []
  let activities = SampleContent.activities

  var visibleActivities: [SampleActivity] {
    selectedFilter == .all
      ? activities
      : activities.filter { $0.filter == selectedFilter }
  }

  /// Pushes an activity detail while preserving the selected filter.
  func open(_ activity: SampleActivity) {
    path.append(.detail(ActivityDetailUIContext(activity: activity)))
  }

  /// Selects an externally addressed section and returns to its root.
  func route(to filter: ActivityFilter) {
    selectedFilter = filter
    path.removeAll()
  }
}

/// The child scope stored directly in Activity's navigation path.
@MainActor
@Observable
final class ActivityDetailUIContext: Identifiable, Hashable {
  nonisolated let id: String
  let activity: SampleActivity

  init(activity: SampleActivity) {
    self.id = activity.id
    self.activity = activity
  }

  nonisolated static func == (lhs: ActivityDetailUIContext, rhs: ActivityDetailUIContext) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

/// Owns Messages' ordered navigation stack.
@MainActor
@Observable
final class MessagesUIContext {
  /// Screens pushed above the Messages root.
  enum Destination: Hashable {
    case conversation(ConversationUIContext)
  }

  var path: [Destination] = []
  let conversations = SampleContent.conversations

  /// Pushes a conversation as an in-app navigation action.
  func open(_ conversation: SampleConversation) {
    path.append(.conversation(ConversationUIContext(conversation: conversation)))
  }

  /// Replaces the stack with the canonical path for an external route.
  func route(toConversationID id: String) {
    path = [
      .conversation(
        ConversationUIContext(conversation: SampleContent.conversation(id: id))
      )
    ]
  }
}

/// The stateful child scope stored directly in Messages' navigation path.
///
/// Sent messages belong to the screen scope. The unsent composer draft remains
/// local to the stateful SwiftUI host because no external caller needs it.
@MainActor
@Observable
final class ConversationUIContext: Identifiable, Hashable {
  nonisolated let id: String
  let conversation: SampleConversation
  private(set) var messages: [SampleMessage]

  init(conversation: SampleConversation) {
    self.id = conversation.id
    self.conversation = conversation
    self.messages = [
      SampleMessage(
        text: conversation.preview,
        isFromCurrentUser: false
      )
    ]
  }

  /// Commits a non-empty draft to this conversation scope.
  func send(_ draft: String) {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    messages.append(SampleMessage(text: text, isFromCurrentUser: true))
  }

  nonisolated static func == (lhs: ConversationUIContext, rhs: ConversationUIContext) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

/// Owns Account's ordered navigation stack.
@MainActor
@Observable
final class AccountUIContext {
  /// Screens pushed above the Account root.
  enum Destination: Hashable {
    case preferences(PreferencesUIContext)
  }

  var path: [Destination] = []

  /// Pushes a fresh preferences scope from the Account root.
  func openPreferences() {
    path.append(.preferences(PreferencesUIContext()))
  }

  /// Replaces the stack with the canonical preferences route.
  func routeToPreferences() {
    path = [.preferences(PreferencesUIContext())]
  }
}

/// The stateful child scope stored directly in Account's navigation path.
@MainActor
@Observable
final class PreferencesUIContext: Identifiable, Hashable {
  nonisolated let id = UUID()
  var notificationsEnabled = true
  var compactAppearance = false

  nonisolated static func == (lhs: PreferencesUIContext, rhs: PreferencesUIContext) -> Bool {
    lhs === rhs
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}
