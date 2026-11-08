# Source implementations and extracted decisions

This records a review of local source files and test definitions on 2026-11-08. The referenced files had no working-tree changes. The original apps were not built or tested, and real authentication was not exercised. Line numbers identify the recorded commits; read the owning source again before changing a current implementation.

The original code is not bundled. Paths in each section are relative to the corresponding repository. Access to those repositories is not required to use this skill; consult them only when you need to examine the implementation evidence in detail.

## Terminology of the skill versus the source apps

In this skill, **Session** means a container created for a specified environment before login. Authentication occurs inside it without changing its identity. It can be disposed from any phase; default logout replaces the entire container with a fresh unauthenticated Session in the same environment. An authenticated child scope is not the Session itself.

The observations below preserve the original applications' terminology, including "login session," `SessionID`, and `AppSessionID`. Those names alone do not establish this contract. Pairs records an identifier preserved across login; PairsNext records a UIContext spanning authentication and a registry keyed by environment and SessionID. MoriDesktop contributes retention/selection and shutdown patterns, but its login-catalog semantics do not define when this skill's outer Session begins. These are design inputs, not a claim that all three apps implement an identical pre-login Session container or logout policy.

## Pairs — Service graphs across authentication and fixed storage destinations

- Repository: `eure/pairs-ios`
- Commit: `3a10d6d73b48754cb712afd9325e4fe83a07402e`
- [ServiceContext](https://github.com/eure/pairs-ios/blob/3a10d6d73b48754cb712afd9325e4fe83a07402e/apps/Pairs/Sources/AppService/Core/Wireframe/ServiceContext.swift#L13)

| Observed implementation | Source / symbol |
| --- | --- |
| Separate Context and ServiceStack types for logged-out and logged-in states | `apps/Pairs/Sources/AppService/Core/Wireframe/ServiceContext.swift:13–19,50–115` |
| Context → Stack → services ownership. Constructing an authenticated graph requires authentication data and user information | `apps/Pairs/Sources/AppService/Core/LoggedIn/LoggedInServiceStack.swift:20–54,175–186` |
| Ends the logged-out stack, constructs and prepares the logged-in stack, and returns it. Reuses the same PersistentDataLayer | `apps/Pairs/Sources/AppService/Core/GroupResolver.swift:88–114` |
| Invalidation resets the namespace before awaiting teardown of the old stack | `apps/Pairs/Sources/AppService/Core/GroupResolver.swift:32–47` |
| PersistentDataLayer fixes its domain and root at construction. Personal defaults, shared defaults, and Keychain have different scopes | `apps/Pairs/Sources/AppService/Core/PersistentDataLayer.swift:159–197` |
| Deactivation retains the session container; destruction invalidates and removes it | `apps/Pairs/Sources/PairsShared/Features/Startup/StartupViewController.swift:554–597` |
| An invalidation flag suppresses some obsolete API-error events | `apps/Pairs/Sources/AppService/Core/LoggedIn/LoggedInServiceStack.swift:243–269,391–396` |

The extracted principles are dependency graphs that are valid for each authentication state, storage destinations fixed at construction, and a distinction between immediate access isolation and later physical deletion.

**Do not generalize these details unchanged:**

- `apps/Pairs/Sources` has no types named `UIContext` or `UIIntent`. Types such as `PJPSessionViewController.Scene` serve corresponding UI responsibilities.
- `ServiceContextIdentifier` is preserved across login (`ServiceContext.swift:104–115`). The ID in `AppRequest/ClientRuntimeSession.swift:5–14` identifies a process launch. Neither automatically identifies an authentication generation.
- Restart in `PairsGroup/PJPSessionViewController.swift:592–633` starts invalidation in a separate Task without awaiting its completion. Restart also does not wait for WebView cookie deletion (`StartupViewController.swift:483–497,599–632`). This is not an example of fully draining work before restart.
- Old directories are cleaned at startup, retaining one based on modification-time ordering (`PersistentDataLayer.swift:620–703`). Namespace generation uses a millisecond timestamp (`AppService/Environment/ServiceEnv.swift:131–156`). This skill requires collision avoidance and protection of active storage, without prescribing these particular mechanisms.
- Rejection of stale results for every request, and removal of all defaults during ordinary logout, were not established. No tests directly covering the entire logout lifecycle were found within the search scope.

Abbreviated paths in this section are relative to `apps/Pairs/Sources/`. A filename without its directory refers to the file of that name in the table.

## PairsNext — UI Context Tree, authentication generations, and retirement recovery

- Repository / commit: the same as Pairs.
- Below, `App/` means `apps/PairsNext/Sources/PairsNext/App/`, and `Core/` means `apps/PairsNext/Sources/AppService/Core/`.
- [UIContext](https://github.com/eure/pairs-ios/blob/3a10d6d73b48754cb712afd9325e4fe83a07402e/apps/PairsNext/Sources/PairsNext/App/UIContext.swift#L6)

| Observed implementation | Source / symbol |
| --- | --- |
| `@MainActor @Observable UIContext` owns the Context Tree before and after authentication | `App/UIContext.swift:6–65` |
| UIIntent is a one-shot external input, routed according to the current session state | `App/UIIntent.swift:4–10`; `App/UIContext.swift:79–96` |
| A root registry shares the resolution Task and UIContext across scenes, keyed by environment and SessionID. Cancelling a waiter does not cancel shared construction | `App/SessionContainerRegistry.swift:55–179` |
| Authentication completion and logout validate the originating context. Obsolete results are rejected without mistakenly ending services that match the current result | `App/UIContext.swift:106–128,177–226` |
| The root retains the Task for a one-time email link to prevent duplicate consumption | `App/UIContext.swift:141–169` |
| Temporary request-admission suspension is separate from permanent termination. Failure restores admission; late non-cooperative responses are rejected after termination | `Core/LoggedIn/LoggedInServiceSession.swift:45–105` |
| Durable SessionID is separate from credentialSlotID. Logout replaces both; failed authentication replaces only the slot | `Core/SessionCatalog.swift:13–34,222–244` |
| Generic persistence is scoped by session; logged-in persistence is scoped by session and slot | `Core/PersistentDataLayer.swift:3–39` |
| Retirement journal → SDK sign-out → defaults cleanup → catalog update. Interrupted retirement is processed before restoration | `Core/FirebaseSessionRuntime.swift:121–178` |
| Cleanup processes only the startup snapshot and acknowledges the journal after success. Failures are retried on a later launch | `Core/FirebaseRetirementCoordinator.swift:19–41` |
| URL inputs for ended sessions are discarded. Deferred inputs are also associated with their destination session | `App/PairsNextApp.swift:260–326` |

**Scope of these design choices:**

- `plugins/pairsnext-ios/skills/pairsnext-development/references/context-tree-guide.md` places only externally controllable screen state in the Context Tree. Screen-local input, focus, progress, alerts, and ordinary screen effects remain in the View.
- `App/SessionView.swift:14–56` recreates the SwiftUI subtree using the context's object identity. This also replaces View-local state at a login boundary.
- The authentication actor does not admit another attempt until rollback finishes. Authentication for an already consumed email link does not stop merely because the calling View is cancelled (`Core/AuthenticationSessionService.swift:341–393`).
- Firebase sign-out requires the current `User` object to match, preventing an old operation from signing out a newer login with the same UID (`apps/PairsNext/Sources/AppService/Library/FirebaseAuthenticationService.swift:151–205`).
- Retaining retired Firebase runtimes in the process and cleaning old slots on the next launch is an SDK-specific decision. Completion of explicitly tracked SDK operations does not prove that all internal SDK activity has stopped (`Core/FirebaseSDKOperationLifetime.swift:4–8,39–68`).
- Latest-wins import callbacks, separate Firebase app names, and StateGraph are product- or library-specific choices. Do not require them in every app.

Behavioral examples are in `apps/PairsNext/Tests/PairsNextTests/`: `UIContextTests.swift`, `LoggedInServiceSessionTests.swift`, `SessionContainerRegistryTests.swift`, `SessionCatalogTests.swift`, `FirebaseRetirementCoordinatorTests.swift`, and `AuthenticationSessionServiceTests.swift`. The real-SDK probes in `FirebaseSDKLifecycleTests.swift:6–8` are limited to fresh apps without a signed-in user. They do not establish that cleanup of credentials for real accounts has been verified.

## MoriDesktop — Retention and selection, save preflight, and shutdown draining

- Repository: `frankyhq/mori`
- Commit: `83043f67fbf001870ede4b0cd27fc26253ad708f`
- Below, `App/` means `apps/desktop/Sources/MoriDesktop/App/`.
- [UIContext](https://github.com/frankyhq/mori/blob/83043f67fbf001870ede4b0cd27fc26253ad708f/apps/desktop/Sources/MoriDesktop/App/UIContext.swift#L4)

| Observed implementation | Source / symbol |
| --- | --- |
| Retained sessions and the selected session are separate and shared across all windows | `App/UIContext.swift:4–47`; `App/MoriDesktop.swift:26–68,118–125` |
| UIIntent requests a scope change; it is not proof of authentication | `App/UIIntent.swift:1–25` |
| Identical transitions join the same Task; conflicting intents are rejected | `App/UIContext.swift:105–127` |
| Ownership is SessionUIContext → Application → immutable PersistentContainer / records / documents / services | `App/Models/SessionUIContext.swift:7–38`; `App/Application.swift:6–46,101–139` |
| Personal storage and defaults are isolated by environment and AppSessionID. Provider credentials use the same namespace. Whisper models are shared | `App/PersistentContainer.swift:5–42` |
| Deselecting drains recording while retaining background work and its owner | `App/Models/SessionUIContext.swift:151–178`; `App/UIContext.swift:129–172` |
| Individual termination saves drafts → retires catalog membership → shuts down and joins work → removes the owner from the registry. Save or retirement failure retains a recoverable owner | `App/Models/SessionUIContext.swift:279–317`; `App/UIContext.swift:174–204` |
| Quit requires all owners to save successfully before closing any owner. Failure restores editing | `App/UIContext.swift:238–270` |
| Application's shutdown Task is idempotent and waits for document writes, runtime shutdown, bootstrap, and providers | `App/Application.swift:162–187` |
| Returns terminateLater to AppKit and replies after asynchronous shutdown. Closing the last window does not quit | `App/MoriDesktop.swift:203–235` |

**Scope of these design choices:**

- Logged-in owners are created and restored through Debug local workspaces. `apps/desktop/AGENTS.md` also identifies Auth0 integration as subsequent work. This is not a completed example of real Mori account authentication in Release.
- `Features/Settings/Application.AgentAuthentication.swift` handles Codex/Claude provider authentication, not Mori account authentication. Invalidating callback admission, checking operation identity, and waiting for backend completion are useful patterns, but their authentication domains must not be confused.
- `LoginSessionStore.end` only retires catalog membership; it retains files, preferences, and provider credentials (`App/LoginSessionStore.swift:76–97`). Do not adopt this as a universal production logout policy.
- An ongoing login restores the same AppSessionID. A new login after retirement gets a new ID, even for the same account. Process quit does not retire catalog membership.
- `MoriProcessing.AppSession` is a runtime for recording, import, and other processing, not a login ID. It is also distinct from `AppSessionID = Identifier<Application>`.

Behavioral examples are in `apps/desktop/Tests/MoriDesktopTests/`: `App/LoginSessionStoreTests.swift` (restart, old storage, environment isolation), `App/UIContextTests.swift` (retention, selection, background generation), `App/SessionUIContextTests.swift` (closing admission and joining work), and `Features/Records/DocumentEditingTests.swift:562,644` (save failures and recovery of hidden sessions).

## Requirements added by this skill

The pre-login, environment-bound Session contract and default whole-Session replacement on logout are the skill's design contract, not a uniform observation of the source apps. Making every commit boundary for obsolete generations, failure phase, storage policy, and fixed cleanup target explicit is implementation guidance derived from these examples. It does not claim that all three apps implement and verify the same mechanisms. A particular SDK, purging all data, retaining multiple Sessions, and a journal remain conditional design choices.
