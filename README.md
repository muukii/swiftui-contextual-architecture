# SwiftUI Contextual Architecture

This repository contains a small SwiftUI routing prototype and an agent skill for the broader Session lifecycle contract below. The current demo represents app-level routing as an explicit **UIModel tree**.

The demo uses a fictional community app with authentication, initial setup, four retained tabs, deep links, app-wide presentations, and restricted states. Names and sample content are deliberately generic so the architecture can be discussed publicly without depending on a real product.

## Session lifecycle contract

The architecture's **Session** is a container created for a specified environment **before login**, not the period after authentication. Its environment and identity are fixed at creation. Login and other session-scoped operations run inside it; authentication success changes its child scope, not the enclosing Session's identity.

```text
App root / Session registry
|-- Session A (environment E, created before login)
|   |-- session-scoped services, storage, and UIContext
|   `-- authentication: unauthenticated -> authenticated child
|-- Session B (another independent container, possibly unauthenticated)
`-- selected SessionID?
```

A Session can be explicitly terminated from any phase. Default logout disposes the entire Session and creates a fresh unauthenticated Session for the same environment with a new identity, instead of resetting and reusing the old container. Disposal must stop/drain owned work and reject obsolete results; replacement alone does not prevent old callbacks or writes from racing with new work. Disposal and physical deletion of persistent data are separate policies.

Retaining a Session, selecting it, and authenticating it are separate concepts. Multiple Sessions can use the same environment with isolated session-scoped resources. Changing a Session's environment means creating or selecting a different container, not mutating the existing one.

**Current demo limitation:** the Swift demo below still uses `AppUIModel.Session` as an authentication-state enum under one root. It does not yet implement independent environment-bound Session containers, whole-Session logout replacement, or multiple retained Sessions. Its existing `UIModel` names and routing behavior are unchanged. The [agent skill](#agent-skill) documents the lifecycle contract for future implementations.

## The idea

Navigation is larger than a single `NavigationPath`. A production-shaped app may have all of these at once:

- an authentication-state boundary such as signed out or signed in;
- a setup or preparation gate before the main UI is ready;
- several tab roots that remain alive while another tab is visible;
- an independent navigation stack in each tab;
- app-wide sheets and blocking layers;
- external requests that arrive before their destination can be shown.

The prototype models that shape explicitly:

```text
external URL or app event
          |
          v
       UIIntent                 one-shot request
          |
          v
      AppUIModel                persistent UI state
      |-- session
      |   |-- signedOut
      |   `-- signedIn
      |       |-- setup
      |       `-- main
      |           |-- preparing
      |           |-- tabs
      |           `-- restricted
      |-- pendingIntent?
      |-- sheet?
      `-- blockingNotice?
```

SwiftUI then projects this state into views.

## Why `UIModel`?

`ViewModel` often suggests one helper object per view. Here, the object has a different responsibility: it describes the intended UI topology, owns the lifetimes of child UI scopes, and handles transitions between them. `UIModel` makes that role explicit while leaving domain models independent of the UI.

The central rule is slightly more precise than “model existence equals screen visibility”:

> A UIModel's existence means that its UI scope is retained. Selection and presentation state determine whether that scope is currently visible.

That distinction matters for tabs. All four tab UIModels can continue to exist while only one tab is selected, preserving each tab's navigation stack.

## `UIIntent` and `UIModel` are different

A `UIIntent` is a one-shot request:

```swift
enum UIIntent {
  case openStory(id: String)
  case showActivity(filter: ActivityFilter)
  case openConversation(id: String)
  case openPreferences
  case showAnnouncement
}
```

The UIModel tree is the durable result after that request is interpreted. For example, `openConversation` selects the Messages tab and installs a conversation UIModel in that tab's canonical navigation path. The intent does not remain the source of truth after routing finishes.

If the app is not ready, the root stores the intent as `pendingIntent`. Authentication, setup, and preparation continue normally; the intent is replayed when the tab container is available.

```text
deep link
   |
   v
UIIntent ---- app not ready ----> pendingIntent
   |                                  |
   | app ready                        | readiness changes
   v                                  v
mutate the UIModel tree <-------------+
```

## Demo topology

The sample exercises the following states:

```text
AppUIModel
|-- session
|   |-- signedOut(SignInUIModel)
|   `-- signedIn(SignedInUIModel)
|       |-- setup(ProfileSetupUIModel)
|       `-- main(MainUIModel)
|           |-- preparing
|           |-- tabs(TabContainerUIModel)
|           |   |-- HomeUIModel
|           |   |-- ActivityUIModel
|           |   |-- MessagesUIModel
|           |   `-- AccountUIModel
|           `-- restricted
|-- sheet?
|-- blockingNotice?
`-- pendingIntent?
```

The four tab UIModels are retained together. Each owns its own typed path, so switching tabs does not destroy another tab's navigation history. App-level presentation state lives above the tabs because it is not part of any one stack.

## What remains local to a view

The architecture does not move every piece of screen state into the UIModel tree.

Use a UIModel when state must outlive a particular view instance, participate in routing, or be controlled externally. Keep ephemeral interaction state in a stateful SwiftUI host.

| State | Owner |
|---|---|
| authentication state (`session` in the current demo), selected tab, paths, presentations | UIModel tree |
| pending external route | root UIModel |
| fetched content needed after view recreation | feature UIModel |
| text-field focus, draft interaction, animation phase | stateful host view |
| value rendering and action closures | state view |

Conceptually:

```text
External State
`-- Stateful View
    `-- State View
```

This keeps the externally controllable shape explicit without turning transient SwiftUI mechanics into global state.

## Running the prototype

Open `ModelArchitecture.xcodeproj` in Xcode and run the `ModelArchitecture` scheme on an iOS Simulator.

The normal path through the demo is:

1. Tap **Sign In**.
2. Complete the two setup steps with **Continue** and **Finish Setup**.
3. Leave the preparation gate with **Enter App**.
4. Explore the retained **Home**, **Activity**, **Messages**, and **Account** tabs.

The floating **Route Lab** button exposes the same routing entry point used by deep links. It can open destinations, show app-level presentations, enter restricted mode, and display a blocking notice. The lab also makes the current UIModel tree and any pending intent observable while experimenting.

## Deep links

The app registers the `uimodel-demo` URL scheme. These examples can be opened from Terminal while the app is installed in the booted simulator:

```bash
xcrun simctl openurl booted 'uimodel-demo://home'
xcrun simctl openurl booted 'uimodel-demo://home/story/story-1'
xcrun simctl openurl booted 'uimodel-demo://activity/mentions'
xcrun simctl openurl booted 'uimodel-demo://messages/conversation/conversation-1'
xcrun simctl openurl booted 'uimodel-demo://account/preferences'
xcrun simctl openurl booted 'uimodel-demo://announcement/welcome'
```

Try opening a destination URL before signing in. The app should retain it as a pending intent and apply it only after the setup and preparation gates have completed.

## Building from the command line

```bash
xcodebuild \
  -project ModelArchitecture.xcodeproj \
  -scheme ModelArchitecture \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Maestro flows

The UI flows cover the ordinary sign-in-to-tabs journey and routing from the Route Lab. With the app installed on a simulator:

```bash
maestro test Maestro/flows/
```

The flows use visible labels for user journeys and the `route-lab-button` accessibility identifier for the developer entry point.

## Design boundaries

The current Swift demo is intentionally a routing prototype, not a complete implementation of the Session lifecycle contract.

- Domain entities and persistence are sample-only.
- `UIIntent` is an input vocabulary, not a second state store.
- A path is appropriate for an ordered stack, but it is not expected to encode the entire app.
- App-wide sheets and blocking UI are modeled separately from per-tab stacks.
- The example favors explicit transitions and inspectable state over framework abstraction.

## Agent Skill

The repository includes the [SwiftUI Contextual Architecture plugin](plugins/swiftui-contextual-architecture/README.md), a self-contained [Agent Plugins 1.0.0](https://agent-plugins.org/specification) package rooted at `plugins/swiftui-contextual-architecture/`.

Its English-language [`swift-app-session-foundation`](plugins/swiftui-contextual-architecture/skills/swift-app-session-foundation/SKILL.md) skill builds environment-bound Session containers that begin before login, UIContext/UIIntent routing, session-owned services, isolated storage, and explicit disposal/replacement lifecycles. It draws on Pairs, PairsNext, and MoriDesktop, with source-specific terminology and limitations recorded separately from the skill's contract in its references.

Invoke `$swift-app-session-foundation` when building or refactoring these boundaries in a client that supports this invocation. The repository-local `.agents/skills/swift-app-session-foundation` link points to the packaged skill, keeping one maintained copy. See the plugin README for validation and distribution instructions.

## Requirements

- Xcode with Swift Observation support
- iOS 17 or later
- Maestro only when running the optional UI flows
