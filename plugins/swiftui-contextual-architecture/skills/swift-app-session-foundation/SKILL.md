---
name: swift-app-session-foundation
description: Build or refactor Swift app foundations for login/logout, UIContext/UIIntent routing, session-owned services, isolated persistence, and ordered cleanup. Use when authentication changes the app's model graph or storage lifetime, including account switching and multiple windows.
---

# Swift App Session Foundation

Implement authentication transitions as changes in ownership of dependencies, work, and storage, as well as changes in the visible UI. Draw on the service ownership tree in Pairs, the Context Tree and session management in PairsNext, and multiwindow ownership and shutdown in MoriDesktop.

This skill builds application foundations. Choose an authentication provider, design a login screen, or configure an authentication server only when the request includes that work. Respect the target application's existing authentication, persistence, and observation libraries. The libraries and type names used by the reference projects are not prerequisites.

## Establish the boundaries

Read the application's entry point, authentication result handlers, service construction, persistence, and window or Scene ownership. Map existing types to the responsibilities below and reuse owners that already exist.

| Responsibility | Lifetime and ownership |
| --- | --- |
| Process / app root | Lives from startup to termination. Coordinates authentication state, the session registry, and account-independent features. |
| UIContext | Owns the Context Tree and selection that represent externally controllable screen state. Provides a boundary for accepting authentication results. Define which windows share it. |
| UIIntent | A one-shot request directed at a UI scope, such as a deep link, notification, or menu action. It is not proof of authentication. |
| Logged-out context | Owns authentication attempts and only the dependencies needed before login. |
| Login/session context | Owns the services, work, and child UI contexts for one login lifetime. |
| Persistent container | Binds storage locations and stores to an immutable environment and owner identity. Recreating a window or recording does not change that binding. |
| Feature / window context | Represents externally controlled screen existence, navigation, and related state. Borrows shared services. Define whether closing it ends the login. |

Do not move all screen-local input, focus, transient progress, or alerts into the Context Tree. Put state that must outlive or be shared beyond a View in the owner with that lifetime. Do not turn UIContext into a general-purpose ViewModel or a runner for every side effect.

Resolve the following from existing requirements. Ask the user only about unresolved choices, and continue work that does not depend on the answers.

- Can the app retain one login or several? Does work continue in an unselected session?
- Does signing in to the same account again restore the previous storage scope or create a new login scope?
- How do explicit logout, authentication expiration, account switching, window closure, and process termination differ?
- Which edits must be saved, credentials removed, business data retained, and caches deleted at logout?
- How are development and production environments, accounts, login lifetimes, and credential generations identified?

Do not infer data or secret deletion policies from type names or reference-project behavior. If a policy is unresolved, build the boundary through which it can be supplied and leave the destructive implementation pending.

## Build the foundation

1. **Define the ownership graph and transitions.** The UI renders the existence and state of contexts. Represent valid dependencies with a login-state enum or an equivalent structure; avoid adding independent authentication booleans to screens or globally replacing services. Specify UI isolation, async work ownership, and the serialization boundary for writes. Use [lifecycle.md](references/lifecycle.md) to implement construction, switching, and termination contracts.
2. **Classify storage.** Fill the table in [storage.md](references/storage.md) with the application's actual data. Bind the environment, identities, paths, and credential references when constructing services. Do not later change a store's destination by consulting a global "current user."
3. **Commit authentication success.** Verify the originating authentication attempt. Publish one context only after its required storage and services are ready. Reject results from invalidated attempts and clean up resources newly owned by those attempts.
4. **Own termination explicitly.** Implement admission control, required saves, retirement, stopping and draining work, closing resources, and applying credential and data policies, including failure states. Neither `deinit`, View disappearance, nor `Task.cancel()` alone establishes completion.
5. **Route UIIntent within the correct lifetime.** Accept only requests the current state can handle. If delivery must wait, define the destination, expiration, and duplicate policy. Do not deliver a previous user's request to the next user. A single giant intent enum for every screen action is unnecessary.
6. **Verify the actual boundaries.** Select applicable scenarios from [verification.md](references/verification.md). Check late completion of old work, save failures, cleanup retries, and restart behavior as well as successful UI transitions.

Document new types with DocC comments explaining what they own, who constructs and ends them, and which lifetime they represent. Document reentrancy, idempotence, and the usable state after failure on termination APIs. Short-lived screen work can remain in the View; one-time authentication operations and session termination need owners that survive for their required lifetime.

## Leave a useful handoff

Alongside code changes, briefly record the ownership graph, transitions and failure policies, data-retention table, completed verification, and unverified behavior. Keep `.tmp/implementation-notes.md` updated with design decisions, deviations, tradeoffs, and unresolved questions. When authentication is stubbed, do not report local validation as verification of real authentication.

Read [source-patterns.md](references/source-patterns.md) when tracing a design choice to its source implementation. It records observed behavior, not a requirement for every application to behave identically. The skill can be used without access to the original repositories.
