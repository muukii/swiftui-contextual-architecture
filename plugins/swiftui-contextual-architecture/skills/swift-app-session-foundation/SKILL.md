---
name: swift-app-session-foundation
description: Build or refactor Swift app foundations around environment-bound Session containers created before login, UIContext/UIIntent routing, isolated persistence, and ordered disposal. Use for login/logout, whole-Session replacement, multiple retained Sessions, and multiwindow ownership.
---

# Swift App Session Foundation

Treat Session as an environment-bound container, not as the period after login. Create it for a specified environment before authentication; start login and other session-scoped work inside it. Authentication changes its children and capabilities, not the identity of the enclosing Session. Draw on the service ownership tree in Pairs, the Context Tree and session management in PairsNext, and multiwindow ownership and shutdown in MoriDesktop without assuming their terminology is identical.

This skill builds application foundations. Choose an authentication provider, design a login screen, or configure an authentication server only when the request includes that work. Respect the target application's existing authentication, persistence, and observation libraries. The libraries and type names used by the reference projects are not prerequisites.

## Session contract

- Bind the environment and Session identity at creation, without requiring an authenticated account. Changing environments requires a different Session.
- Own pre-login UI, authentication attempts, session-scoped services and storage, and any authenticated child scope within that Session. Construct authenticated-only dependencies only when needed.
- Allow explicit termination from any phase, including before or during login. Disposal closes admission, invalidates old results, stops and drains owned work, and releases resources; dropping a reference alone is not disposal.
- Use whole-Session replacement as the default logout pattern: end the old Session and create a fresh unauthenticated Session for the same environment with a new identity. Do not merely reset the old container's authentication flag or reuse its services. Establish isolation before the replacement accepts work; retained cleanup must target only the old Session.
- Multiple retained Sessions may be unauthenticated or authenticated. Selection is not ownership, and deselection is not disposal.
- Separate disposal from physical data deletion. Define restoration, credential removal, and data-retention policies explicitly.

## Establish the boundaries

Read the application's entry point, authentication result handlers, service construction, persistence, and window or Scene ownership. Map existing types to the responsibilities below and reuse owners that already exist.

| Responsibility | Lifetime and ownership |
| --- | --- |
| Process / app root | Lives from startup to termination. Owns the Session registry, selection, construction/replacement, and account-independent features. It is not itself the per-environment Session. |
| Session container | Begins before login with a fixed environment and identity. Owns session-scoped dependencies, UI state, authentication attempts, and authenticated child scopes until explicit termination. |
| UIContext | Represents externally controllable screen state through the Context Tree and selection. Route authentication results through the owning Session. Define app-level versus per-Session UIContext ownership and which windows share it. |
| UIIntent | A one-shot request directed at a UI scope, such as a deep link, notification, or menu action. It is not proof of authentication. |
| Unauthenticated child scope | Lives inside a Session before login. Uses only pre-login dependencies; authentication attempts remain owned for their required lifetime. |
| Authenticated child scope | Owns authenticated services, work, and child UI contexts within the enclosing Session. Its lifetime is not the definition of Session. |
| Persistent container | Binds storage locations and stores to the Session's immutable environment and identity. Account- or credential-specific children are bound when authenticated. Recreating a window or recording does not change those bindings. |
| Feature / window context | Represents externally controlled screen existence, navigation, and related state. Borrows Session-owned services. Define whether closing it ends the Session. |

Do not move all screen-local input, focus, transient progress, or alerts into the Context Tree. Put state that must outlive or be shared beyond a View in the owner with that lifetime. Do not turn UIContext into a general-purpose ViewModel or a runner for every side effect.

Resolve the following from existing requirements. Ask the user only about unresolved choices, and continue work that does not depend on the answers.

- Can the app retain one Session or several, including unauthenticated ones? Does work continue in an unselected Session?
- Which Sessions survive a process restart? Which account data, if any, may a fresh Session explicitly recover without reusing retired Session resources?
- How do explicit logout, authentication expiration, account switching, window closure, and process termination differ?
- Which edits must be saved, credentials removed, business data retained, and caches deleted at logout?
- How are environments, Session identities, accounts, authentication attempts, and runtime or credential generations identified?

Do not infer data or secret deletion policies from type names or reference-project behavior. If a policy is unresolved, build the boundary through which it can be supplied and leave the destructive implementation pending.

## Build the foundation

1. **Define the ownership graph and transitions.** Create the Session before login and represent authentication state inside it with an enum or equivalent structure. The UI renders the existence and state of contexts; an authentication-state enum alone is not a Session container. Avoid independent authentication booleans on screens or globally replacing services. Specify UI isolation, async work ownership, and the serialization boundary for writes. Use [lifecycle.md](references/lifecycle.md) for construction, switching, replacement, and termination contracts.
2. **Classify storage.** Fill the table in [storage.md](references/storage.md) with the application's actual data. Bind environment and Session identity before login, and account or credential references when constructing authenticated children. Do not later change a store's destination by consulting a global "current user."
3. **Commit authentication success inside the Session.** Verify the originating Session, attempt, and generation. Publish the authenticated child only after its required storage and services are ready, preserving the enclosing Session identity. Reject results from invalidated attempts or ended Sessions and clean up only resources owned by those attempts.
4. **Own termination and replacement explicitly.** Implement disposal from every phase, admission control, required saves, retirement, stopping and draining work, closing resources, and credential/data policies, including failure states. For logout, replace the whole Session by default. Neither `deinit`, View disappearance, nor `Task.cancel()` alone establishes completion or protects the replacement from old work.
5. **Route UIIntent within the correct lifetime.** Accept only requests the current state can handle. If delivery must wait, define the destination Session, expiration, and duplicate policy. Do not deliver an ended Session's request to its replacement or a previous user's request to the next user. A single giant intent enum for every screen action is unnecessary.
6. **Verify the actual boundaries.** Select applicable scenarios from [verification.md](references/verification.md). Check late completion of old work, save failures, cleanup retries, and restart behavior as well as successful UI transitions.

Document new types with DocC comments explaining what they own, who constructs and ends them, and which lifetime they represent. Document reentrancy, idempotence, and the usable state after failure on termination APIs. Short-lived screen work can remain in the View; one-time authentication operations and session termination need owners that survive for their required lifetime.

## Leave a useful handoff

Alongside code changes, briefly record the ownership graph, transitions and failure policies, data-retention table, completed verification, and unverified behavior. Keep `.tmp/implementation-notes.md` updated with design decisions, deviations, tradeoffs, and unresolved questions. When authentication is stubbed, do not report local validation as verification of real authentication.

Read [source-patterns.md](references/source-patterns.md) when tracing a design choice to its source implementation. It records observed behavior, not a requirement for every application to behave identically. The skill can be used without access to the original repositories.
