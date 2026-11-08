# SwiftUI Contextual Architecture

A SwiftUI demo of **environment-bound Session containers**, **UIContext** trees, and one-shot **UIIntent** routing. It implements the ownership model in the repository's [Session foundation skill](plugins/swiftui-contextual-architecture/skills/swift-app-session-foundation/SKILL.md).

Authentication and storage are deliberately simulated. Production and Staging are separate mock environments; neither connects to a server.

## Session is a container, not a login period

A Session starts **before login** with a fixed environment and UUID. Its services, in-memory storage, and UIContext already exist. Authentication creates an authenticated child inside that same container.

```text
AppUIContext (process-owned registry and selection)
|-- sessions[]
|   |-- Session A (Production, immutable UUID)
|   |   |-- SessionServices -> SessionStore
|   |   |-- SessionUIContext
|   |   |   |-- authentication
|   |   |   |   |-- signedOut(SignInUIContext)
|   |   |   |   |-- authenticating(attemptID, account)
|   |   |   |   |-- signedIn(SignedInUIContext)
|   |   |   |   |   |-- setup(ProfileSetupUIContext)
|   |   |   |   |   `-- main(MainUIContext)
|   |   |   |   |       |-- surface: preparing / tabs / restricted
|   |   |   |   |       `-- retained TabContainerUIContext
|   |   |   |   |           |-- HomeUIContext
|   |   |   |   |           |-- ActivityUIContext
|   |   |   |   |           |-- MessagesUIContext
|   |   |   |   |           `-- AccountUIContext
|   |   |   |   `-- closing / closed
|   |   |   |-- pendingIntent?
|   |   |   |-- sheet?
|   |   |   `-- blockingNotice?
|   |   `-- AuthenticatedServices? (created only on login success)
|   `-- Session B (independent, possibly unauthenticated)
|-- selectedSessionID?
|-- retained termination tasks
`-- mock transport and bounded diagnostic history
```

- **Creation** selects an environment, not an account.
- **Login** runs inside an existing Session. Success preserves its UUID, services, storage, and UIContext.
- **Selection** only changes which retained container is shown. Other Sessions keep their work, authentication, and navigation state.
- **Disposal** is allowed before login, during login, setup, preparation, or normal use.
- **Logout** ends the whole old Session, then creates a fresh unauthenticated one for the same environment. It never just resets an authentication flag.
- **Environment changes** require creating or selecting another Session.

All transitions and store writes are serialized on the main actor. Service tasks belong to the Session, not to a View or a mutable global “current account.”

## Try the demo

Open `ModelArchitecture.xcodeproj` and run the `ModelArchitecture` scheme on an iOS Simulator. One unauthenticated Production Session is created on launch. The top bar always shows the selected Session's environment, short UUID, and state.

### 1. Observe login inside an existing container

1. Open **Sessions**. Note the **Session ID**, **Stored value**, and **Ownership details**.
2. **Increment Session Value** before login.
3. Tap **Done**, choose Taylor or Jordan, then **Sign In**.
4. Authentication remains pending until **Complete Sign In** or **Fail Sign In** is tapped.
5. On success, complete **Continue → Finish Setup → Enter App**.
6. Reopen **Sessions**: the Session, pre-login service, and storage identities are unchanged; only authenticated services were added.

Failure returns to a retryable signed-out child in the same Session. These are mock accounts, not credentials.

### 2. Retain and switch containers

In **Sessions**, scroll to **New container**, choose Production or Staging, and tap **Create Session**. The previous Session is not signed out. Select either row under **Retained containers** to return to it.

Create multiple containers even for the same environment/account. Their stored values and navigation paths remain independent. View-local drafts are not promised to survive a switch; externally controlled UIContext state is.

### 3. Dispose during authentication or background work

1. Start **Sign In**, then tap **Dispose During Sign In**; alternatively start **Background Write** in the lab and **Dispose Session**.
2. The Session enters **Closing** immediately: new work and writes are rejected, pending routes and presentations are discarded.
3. The mock SDK deliberately ignores cancellation. **Deliver Pending Callbacks** on the closing screen, or use **Sessions → Callbacks**.
4. Old results are rejected. Only after owned work drains is storage closed and the Session removed.
5. **Sessions → Events** shows the rejection, close, disposal, and final old stored value.

You can create or select other Sessions while a retired one is draining. Delivering its callbacks never changes another container's store.

### 4. Log out by replacing the whole Session

From **Account** or the Session Lab, tap **Log Out & Replace Session**. The replacement has the **same environment**, but new Session/service/storage UUIDs, value zero, and no authenticated child or inherited route.

For a visible drain, start a background write first. Replacement waits for callback delivery and old storage closure. Selecting another Session during that wait is respected; completion retains the replacement without stealing selection.

## Termination and failure policy

```text
close UI/service/write admission and invalidate pending routing
  -> request cancellation
  -> await every owned operation (including cancellation-ignoring callbacks)
  -> close the old store
  -> release authenticated children and mark closed
  -> remove from registry
  -> optionally create fresh same-environment Session
```

`Session.terminate()` and `AppUIContext.endSession(_:replacing:)` retain their tasks independently of View lifetime. Repeated same-policy requests join the existing shutdown; conflicting dispose/replace requests are rejected. The old container cannot become active again.

A callback must pass the original service's admission/cancellation checks. Authentication additionally checks the current attempt inside its originating Session. A Session UUID also acts as the lifetime boundary across logout/relogin.

There is **no timeout** in this deterministic mock: forgetting to deliver an outstanding callback leaves it closing, not falsely “disposed.” Authentication failures are retryable; background request failures leave the value unchanged. The in-memory close cannot fail. Disk-save failures, cleanup retries, credential deletion, and remote revocation need real integrations and their own policies; none is silently treated as successful here.

## UIContext and UIIntent

**UIContext** represents retained UI scope, topology, selection, paths, and presentation. It is not the general owner of networking or a helper object for every View.

> Existence means the UI scope is retained. Selection and presentation determine whether it is visible.

**UIIntent** is a one-shot routing request, not authentication evidence or a second state store. For example, `openConversation` selects Messages and installs its canonical path. Lifecycle actions call the owning Session or registry directly rather than joining one giant intent enum.

The four tab contexts are retained together; restricted mode hides rather than destroys them. Session-wide sheets and blocking notices sit outside their navigation paths. **Route Lab** exposes these transitions and the current context tree.

| State / operation | Owner |
|---|---|
| retained Sessions and global selection | AppUIContext |
| authentication attempts, background work, shutdown | Session / SessionServices |
| authentication UI, pending route, tabs, paths, presentation | SessionUIContext and children |
| committed sample message, bookmark, preference state | feature UIContext |
| form draft, focus, mock account picker, lab inspector page | View-local state |

The app owns one registry outside `WindowGroup`. The current target is single-scene; it does not demonstrate independent multiwindow selection. View disappearance does not dispose a Session.

## Storage and restoration boundaries

| Scope | Actual data in this demo | Lifetime / retention |
|---|---|---|
| app | registry, selection, mock callback broker, last 100 lifecycle events / 10 disposal records | process memory only; diagnostics hold values, not Session references |
| environment | Production / Staging destination enum | immutable per Session; no shared mutable environment store |
| Session | counter and namespace `Environments/<environment>/Sessions/<UUID>` | constructed before login; writes rejected on retirement, closed after drain |
| authenticated child | mock account and new service UUID | created after successful attempt, released after shutdown |
| feature / operation | tab paths, committed sample state, pending callbacks | owning UIContext or service task |
| account / credentials | no persistent account database, token, cookie, or Keychain entry | not implemented; no deletion or revocation performed |

The namespace is diagnostic: **no directory is created**. Disposal closes an in-memory store; it does not claim physical deletion. Restart creates a fresh Production Session with empty state; no Session catalog or credential restoration exists. Forced process termination cannot guarantee async draining. Persistent-data recovery and destructive cleanup policies remain outside this mock.

## Deep links

The app registers `uicontext-demo`; `uimodel-demo` remains a compatibility alias.

```bash
xcrun simctl openurl booted 'uicontext-demo://home/story/story-1'
xcrun simctl openurl booted 'uicontext-demo://activity/mentions'
xcrun simctl openurl booted 'uicontext-demo://messages/conversation/conversation-1'
xcrun simctl openurl booted 'uicontext-demo://account/preferences'
xcrun simctl openurl booted 'uicontext-demo://announcement/welcome'
```

Without a target, the selected Session is captured **when the URL arrives**, not when it becomes ready. Append `?session=<full-Session-UUID>` to address another retained container without changing selection. Invalid, duplicate, unknown, or closing Session targets are rejected, never rerouted to the selected one. Route Lab operates only on its own Session.

Routes requiring tabs wait through authentication, setup, preparation, or restriction. The queue holds the **latest intent only**; a newer deferred intent replaces the previous one. It has no wall-clock expiry, but expires on Session disposal. Logout never transfers it to the replacement, even for the same account.

## Verification

Pure model tests compile the same sources as the app using Swift Package Manager (macOS 14+, Swift 6+), without a simulator, network, sleeps, or extra dependencies:

```bash
swift test
```

Tests cover pre-login creation, same-Session authentication, retries, multiple retained containers, selection/navigation retention, disposal before/during login, ordered draining and late-result rejection, whole-Session replacement, duplicate shutdown, selection during shutdown, same-account relogin, targeted/deferred routes, and Session release / fresh-launch state.

Build the iOS views separately:

```bash
xcodebuild \
  -project ModelArchitecture.xcodeproj \
  -scheme ModelArchitecture \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### XCUITest — code-managed UI regressions

The shared `ModelArchitecture` scheme includes the `ModelArchitectureUITests` target. Open the project and use **Product → Test**, or choose an installed Simulator from `xcrun simctl list devices available` and run:

```bash
xcodebuild \
  -project ModelArchitecture.xcodeproj \
  -scheme ModelArchitecture \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -parallel-testing-enabled NO \
  -resultBundlePath .tmp/SessionUITests.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Use a new result-bundle path for each run; Xcode does not overwrite an existing `.xcresult`. The bundle contains assertions, activities, and failure screenshots/accessibility hierarchies.

For local iteration, add `-collect-test-diagnostics never` to skip slow Simulator sysdiagnose collection after failures; test assertions and attachments are still recorded.

[`SessionUITests`](ModelArchitectureUITests/SessionUITests.swift) drives the real app through XCUITest, with no test-only lifecycle hooks. Each case launches a fresh process and verifies the initial unauthenticated Production container. UUIDs are read from the UI and compared, never hard-coded. State waits and bounded scrolling replace fixed sleeps. The cases cover:

- authentication success/failure with unchanged ownership, account-derived profile drafts, and fresh logout replacement;
- simultaneously authenticated containers with independent values, retained navigation/preferences, and selection;
- shutdown waiting for manually delivered callbacks, rejection of late writes/authentication, and selection during replacement;
- pre-login disposal and recreation, Session-bound deferred deep links, tabs, Route Lab, restriction restoration, and the legacy URL alias.

These replace the previous Maestro flows. Pure model tests remain separate (`swift test`); the UI test target is not part of the Swift package.

### Devin — separately defined screen-interaction cases

[`Tests/DevinE2E.md`](Tests/DevinE2E.md) defines eight repeatable cases for Devin: starting conditions, actions, expected UI evidence, ownership comparisons, and a result template. Ask Devin to run specified case IDs against a revision and record the interaction. This is a reusable test specification, **not** an executable script or a permanent pass/fail report.

XCUITest results, Devin-operated results, and recordings are distinct artifacts. Neither compilation nor model tests alone proves rendered UI behavior; a recording proves one run, not automatic future execution. Real authentication, durable persistence, and multiwindow behavior remain outside this mock's verified contract.

## Agent Skill

The repository includes the [SwiftUI Contextual Architecture plugin](plugins/swiftui-contextual-architecture/README.md), a self-contained [Agent Plugins 1.0.0](https://agent-plugins.org/specification) package rooted at `plugins/swiftui-contextual-architecture/`.

Its English-language [`swift-app-session-foundation`](plugins/swiftui-contextual-architecture/skills/swift-app-session-foundation/SKILL.md) skill builds environment-bound Session containers that begin before login, UIContext/UIIntent routing, session-owned services, isolated storage, and explicit disposal/replacement lifecycles. It draws on Pairs, PairsNext, and MoriDesktop, with source-specific terminology and limitations recorded separately in its references.

Invoke `$swift-app-session-foundation` in clients that support this invocation. The repository-local `.agents/skills/swift-app-session-foundation` link points to the packaged skill, keeping one maintained copy. See the plugin README for validation and distribution instructions.

## Requirements

- Xcode with Swift Observation support; iOS 17 or later
- macOS 14+ and Swift 6+ for `swift test`
- XCUITest uses the existing Xcode installation; no third-party UI testing framework is required
